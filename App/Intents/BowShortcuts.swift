import AppIntents
import SwiftData

struct LogBowTransactionIntent: AppIntent {
  static var title: LocalizedStringResource = "Log a Transaction"
  static var description = IntentDescription("Record an expense in your Bow budget.")

  @Parameter(title: "Amount") var amount: Double
  @Parameter(title: "Payee") var payee: String
  @Parameter(title: "Account") var account: BowAccountEntity
  @Parameter(title: "Envelope") var envelope: BowEnvelopeEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$amount) at \(\.$payee) from \(\.$envelope) using \(\.$account)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0, amount.isFinite, amount < Double(Int64.max) / 100 else {
      throw BowShortcutError.invalidAmount
    }
    let minor = Int64((amount * 100).rounded())
    let accountID = account.id, envelopeID = envelope.id, payee = payee
    let currencyCode = try await MainActor.run {
      let context = try BowModelStore.shared().mainContext
      guard let source = try context.fetch(FetchDescriptor<BudgetAccount>()).first(where: { $0.id == accountID }),
            source.closedAt == nil else { throw BowShortcutError.accountNotFound }
      do {
        try BudgetCommands.addTransaction(
          kind: .expense, account: source, destination: nil, envelopeID: envelopeID,
          amountMinor: minor, date: Date(), payee: payee, notes: "", in: context
        )
      } catch {
        throw BowShortcutError.couldNotRecord(error.localizedDescription)
      }
      return source.currencyCode
    }
    return .result(dialog: "Recorded \(BudgetMoney.formatted(minor, currencyCode: currencyCode)) at \(payee) in Bow.")
  }
}

struct CheckBowEnvelopeIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Envelope Balance"
  static var description = IntentDescription("Ask how much is available in a Bow envelope.")

  @Parameter(title: "Envelope") var envelope: BowEnvelopeEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Check \(\.$envelope)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let envelopeID = envelope.id
    let container = try await MainActor.run { try BowModelStore.shared() }
    let snapshot = try await BudgetSnapshotRepository(modelContainer: container).snapshot(month: Date())
    let (name, currency) = try await MainActor.run {
      let context = container.mainContext
      guard let selected = try context.fetch(FetchDescriptor<BudgetEnvelope>()).first(where: { $0.id == envelopeID })
      else { throw BowShortcutError.envelopeNotFound }
      let currency = try context.fetch(FetchDescriptor<BudgetProfile>()).first?.currencyCode ?? "USD"
      return (selected.name, currency)
    }
    let amount = snapshot.available(for: envelopeID)
    return .result(dialog: "\(name) has \(BudgetMoney.formatted(amount, currencyCode: currency)) available.")
  }
}

struct BowAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogBowTransactionIntent(),
      phrases: ["Log a transaction in \(.applicationName)"],
      shortTitle: "Log Transaction",
      systemImageName: "plus"
    )
    AppShortcut(
      intent: CheckBowEnvelopeIntent(),
      phrases: ["Check an envelope in \(.applicationName)"],
      shortTitle: "Check Envelope",
      systemImageName: "square.grid.2x2.fill"
    )
  }
}

// MARK: - Entities

/// An open cash or credit card account, as Siri and Shortcuts offer it.
struct BowAccountEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
  static var defaultQuery = BowAccountQuery()
  var id: UUID
  var name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BowAccountQuery: EntityStringQuery {
  func entities(for identifiers: [UUID]) async throws -> [BowAccountEntity] {
    try await all().filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [BowAccountEntity] {
    try await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
  }

  func suggestedEntities() async throws -> [BowAccountEntity] {
    try await all()
  }

  private func all() async throws -> [BowAccountEntity] {
    try await MainActor.run {
      try BowModelStore.shared().mainContext.fetch(FetchDescriptor<BudgetAccount>())
        .filter { ($0.kind == .cash || $0.kind == .credit) && $0.closedAt == nil }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { BowAccountEntity(id: $0.id, name: $0.name) }
    }
  }
}

/// A spending envelope (not a card payment), as Siri and Shortcuts offer it.
struct BowEnvelopeEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Envelope"
  static var defaultQuery = BowEnvelopeQuery()
  var id: UUID
  var name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BowEnvelopeQuery: EntityStringQuery {
  func entities(for identifiers: [UUID]) async throws -> [BowEnvelopeEntity] {
    try await all().filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [BowEnvelopeEntity] {
    try await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
  }

  func suggestedEntities() async throws -> [BowEnvelopeEntity] {
    try await all()
  }

  private func all() async throws -> [BowEnvelopeEntity] {
    try await MainActor.run {
      try BowModelStore.shared().mainContext.fetch(FetchDescriptor<BudgetEnvelope>())
        .filter { $0.paymentAccountID == nil && !$0.isHidden }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { BowEnvelopeEntity(id: $0.id, name: $0.name) }
    }
  }
}

private enum BowShortcutError: Error, CustomLocalizedStringResourceConvertible {
  case invalidAmount
  case accountNotFound
  case envelopeNotFound
  case couldNotRecord(String)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .invalidAmount: "Enter an amount greater than zero."
    case .accountNotFound: "That account isn’t in Bow anymore. Choose another one."
    case .envelopeNotFound: "That envelope isn’t in Bow anymore. Choose another one."
    case .couldNotRecord(let reason): "Bow couldn’t record this transaction. \(reason)"
    }
  }
}
