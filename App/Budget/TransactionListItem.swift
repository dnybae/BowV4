import Foundation

struct TransactionListItem: Identifiable, Sendable, Equatable {
  var id: UUID
  var accountID: UUID
  var transferAccountID: UUID?
  var envelopeID: UUID?
  var date: Date
  var createdAt: Date
  var amountMinor: Int64
  var payee: String
  var merchantDomain: String?
  var kindRaw: String
  var sourceRaw: String
  var needsApproval: Bool
  var accountName: String
  var envelopeName: String?
  var scheduleID: UUID? = nil
  var isCleared = false
  var isBeforeStart = false

  var kind: BudgetTransactionKind {
    BudgetTransactionKind(rawValue: kindRaw) ?? .expense
  }

  var isBalanceAdjustment: Bool {
    sourceRaw == BudgetTransaction.balanceAdjustmentSource
  }

  /// Same rule as `BudgetTransaction.needsEnvelope`.
  var needsEnvelope: Bool {
    kind == .expense && envelopeID == nil && !isBalanceAdjustment && !isBeforeStart
  }
}
