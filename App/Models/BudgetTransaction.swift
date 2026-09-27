import Foundation
import SwiftData

@Model
final class BudgetTransaction {
  var id: UUID = UUID()
  var accountID: UUID = UUID()
  var transferAccountID: UUID? = nil
  var envelopeID: UUID? = nil
  var date: Date = Date()
  var createdAt: Date = Date()
  var amountMinor: Int64 = 0
  var payee: String = ""
  var notes: String = ""
  var kindRaw: String = BudgetTransactionKind.expense.rawValue
  var isCleared: Bool = false
  var sourceRaw: String = "manual"
  var externalKey: String? = nil
  var needsApproval: Bool = false

  var kind: BudgetTransactionKind {
    BudgetTransactionKind(rawValue: kindRaw) ?? .expense
  }

  init(
    accountID: UUID,
    transferAccountID: UUID? = nil,
    envelopeID: UUID? = nil,
    date: Date,
    amountMinor: Int64,
    payee: String,
    notes: String,
    kind: BudgetTransactionKind
  ) {
    self.accountID = accountID
    self.transferAccountID = transferAccountID
    self.envelopeID = envelopeID
    self.date = date
    self.amountMinor = amountMinor
    self.payee = payee
    self.notes = notes
    self.kindRaw = kind.rawValue
  }
}
