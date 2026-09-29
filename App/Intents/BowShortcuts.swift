import AppIntents
import SwiftData

struct LogBowTransactionIntent: AppIntent {
  static var title: LocalizedStringResource = "Log a Transaction"
  static var description = IntentDescription("Record an expense in your Bow budget.")

  @Parameter(title: "Amount") var amount: Double
  @Parameter(title: "Payee") var payee: String
  @Parameter(title: "Account") var account: String
  @Parameter(title: "Envelope") var envelope: String?

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0, amount.isFinite, amount < Double(Int64.max) / 100 else {
      throw BowShortcutError.invalidAmount
    }
    let container = try BowModelStore.makeContainer()
    let context = container.mainContext
    let accounts = try context.fetch(FetchDescriptor<BudgetAccount>())
    let matchingAccounts = accounts.filter { $0.name.localizedCaseInsensitiveCompare(account) == .orderedSame }
    guard matchingAccounts.count == 1, let source = matchingAccounts.first,
          source.kind == .cash || source.kind == .credit else {
      throw BowShortcutError.accountNotFound
    }
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let matchingEnvelopes = envelope.map { requested in
      envelopes.filter { $0.paymentAccountID == nil &&
        $0.name.localizedCaseInsensitiveCompare(requested) == .orderedSame }
    } ?? []
    if envelope != nil && matchingEnvelopes.count != 1 { throw BowShortcutError.envelopeNotFound }
    let selected = matchingEnvelopes.first
    let minor = Int64((amount * 100).rounded())
    do {
      try BudgetCommands.addTransaction(
        kind: .expense, account: source, destination: nil, envelopeID: selected?.id,
        amountMinor: minor, date: Date(), payee: payee, notes: "Added with Siri",
        in: context
      )
    } catch { throw BowShortcutError.couldNotRecord }
    return .result(dialog: "Recorded \(BudgetMoney.formatted(minor, currencyCode: source.currencyCode)) at \(payee) in Bow.")
  }
}

struct CheckBowEnvelopeIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Envelope Balance"
  static var description = IntentDescription("Ask how much is available in a Bow envelope.")

  @Parameter(title: "Envelope") var envelope: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let container = try BowModelStore.makeContainer()
    let context = container.mainContext
    let accounts = try context.fetch(FetchDescriptor<BudgetAccount>())
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let matches = envelopes.filter { $0.name.localizedCaseInsensitiveCompare(envelope) == .orderedSame }
    guard matches.count == 1, let selected = matches.first else { throw BowShortcutError.envelopeNotFound }
    let snapshot = BudgetLedger.snapshot(
      month: Date(), accounts: accounts, envelopes: envelopes,
      allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()),
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>())
    )
    let amount = selected.paymentAccountID.map { snapshot.paymentAvailable[$0, default: 0] }
      ?? snapshot.available(for: selected.id)
    let currency = try context.fetch(FetchDescriptor<BudgetProfile>()).first?.currencyCode ?? "USD"
    return .result(dialog: "\(selected.name) has \(BudgetMoney.formatted(amount, currencyCode: currency)) available.")
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

private enum BowShortcutError: Error, CustomLocalizedStringResourceConvertible {
  case invalidAmount
  case accountNotFound
  case envelopeNotFound
  case couldNotRecord

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .invalidAmount: "Enter an amount greater than zero."
    case .accountNotFound: "Choose one existing cash or credit card account by name."
    case .envelopeNotFound: "Choose one existing envelope by name."
    case .couldNotRecord: "Bow couldn't record this transaction. Check the account and try again."
    }
  }
}
