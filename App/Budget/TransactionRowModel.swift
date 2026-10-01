import Foundation

/// Everything a transaction row shows, built once from whichever record the screen has.
/// Keeps display rules (titles, attention states, subtitles) in one tested place.
struct TransactionRowModel: Identifiable, Equatable {
  var id: String
  var title: String
  /// Name used to find the merchant logo. Empty for transfers, which show a transfer symbol.
  var logoName: String
  var merchantDomain: String?
  var kind: BudgetTransactionKind
  var accountName: String
  var envelopeName: String?
  var amountMinor: Int64
  var state: State

  enum State: Equatable {
    case normal
    /// At the bank but not settled. The row is dimmed.
    case pending(String)
    /// The user needs to do something. Shown with an amber status line.
    case attention(String, symbol: String)
    /// A scheduled bill that's due. Shown with a blue status line.
    case scheduled(String)
  }

  var isInflow: Bool { amountMinor > 0 }

  /// The line under the title, without the parts the current screen already makes obvious.
  func subtitle(hiding options: TransactionRowOptions) -> String? {
    let parts = [
      options.contains(.hidesEnvelope) ? nil : envelopeName,
      options.contains(.hidesAccount) ? nil : accountName
    ].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  static func title(payee: String, kind: BudgetTransactionKind) -> String {
    if kind == .transfer { return "Transfer" }
    return payee.isEmpty ? "Transaction" : payee
  }

  /// Needs approval wins over a missing envelope; both need the user.
  static func state(needsApproval: Bool, kind: BudgetTransactionKind, envelopeID: UUID?) -> State {
    if needsApproval { return .attention("Needs review", symbol: "exclamationmark.circle.fill") }
    if kind == .expense && envelopeID == nil {
      return .attention("Choose an envelope", symbol: "tray.and.arrow.down.fill")
    }
    return .normal
  }
}

/// Parts of a row a screen can hide because its context already says them.
struct TransactionRowOptions: OptionSet {
  let rawValue: Int
  /// On an account's ledger every row is that account.
  static let hidesAccount = TransactionRowOptions(rawValue: 1 << 0)
  /// On an envelope's activity every row is that envelope.
  static let hidesEnvelope = TransactionRowOptions(rawValue: 1 << 1)
}

extension TransactionRowModel {
  /// - Parameter amountMinor: Overrides the stored amount, e.g. a transfer seen from its receiving account.
  init(_ item: TransactionListItem, amountMinor: Int64? = nil) {
    self.init(
      id: item.id.uuidString,
      title: Self.title(payee: item.payee, kind: item.kind),
      logoName: item.kind == .transfer ? "" : item.payee,
      merchantDomain: item.kind == .transfer ? nil : item.merchantDomain,
      kind: item.kind,
      accountName: item.accountName,
      envelopeName: item.envelopeName,
      amountMinor: amountMinor ?? item.amountMinor,
      state: Self.state(needsApproval: item.needsApproval, kind: item.kind, envelopeID: item.envelopeID)
    )
  }

  init(_ transaction: BudgetTransaction, accountName: String, envelopeName: String?) {
    self.init(
      id: transaction.id.uuidString,
      title: Self.title(payee: transaction.payee, kind: transaction.kind),
      logoName: transaction.kind == .transfer ? "" : transaction.payee,
      merchantDomain: transaction.kind == .transfer ? nil : transaction.merchantDomain,
      kind: transaction.kind,
      accountName: accountName,
      envelopeName: envelopeName,
      amountMinor: transaction.amountMinor,
      state: Self.state(
        needsApproval: transaction.needsApproval, kind: transaction.kind, envelopeID: transaction.envelopeID
      )
    )
  }

  init(_ item: SpendingTimelineItem) {
    let state: State
    switch item.status {
    case .none: state = .normal
    case .pending, .pendingEntered: state = .pending(item.status?.rowLabel ?? "Pending")
    case .scheduled: state = .scheduled(SpendingTimelineStatus.scheduled.rowLabel)
    case .some(let status): state = .attention(status.rowLabel, symbol: status.systemImage)
    }
    self.init(
      id: item.id,
      title: item.title.isEmpty ? "Transaction" : item.title,
      logoName: item.kind == .transfer ? "" : item.title,
      merchantDomain: item.kind == .transfer ? nil : item.merchantDomain,
      kind: item.kind,
      accountName: item.accountName,
      envelopeName: item.envelopeName,
      amountMinor: item.amountMinor,
      state: state
    )
  }
}
