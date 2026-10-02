import Foundation
import SwiftData

@Model
final class BudgetTransaction {
  #Index<BudgetTransaction>(
    [\.id],
    [\.date, \.createdAt, \.id],
    [\.accountID, \.date],
    [\.transferAccountID, \.date],
    [\.envelopeID, \.date],
    [\.needsApproval],
    [\.kindRaw, \.envelopeID, \.sourceRaw],
    [\.externalKey],
    [\.scheduleID, \.scheduledFor]
  )
  var id: UUID = UUID()
  var accountID: UUID = UUID()
  var transferAccountID: UUID? = nil
  var envelopeID: UUID? = nil
  var date: Date = Date()
  var createdAt: Date = Date()
  var amountMinor: Int64 = 0
  var payee: String = ""
  var merchantDomain: String? = nil
  var notes: String = ""
  var kindRaw: String = BudgetTransactionKind.expense.rawValue
  var isCleared: Bool = false
  var destinationIsCleared: Bool = false
  var reconciledAt: Date? = nil
  var destinationReconciledAt: Date? = nil
  var sourceRaw: String = "manual"
  var externalKey: String? = nil
  var needsApproval: Bool = false
  var scheduleID: UUID? = nil
  var scheduledFor: Date? = nil

  var kind: BudgetTransactionKind {
    BudgetTransactionKind(rawValue: kindRaw) ?? .expense
  }

  static let balanceAdjustmentSource = "balanceAdjustment"
  var isBalanceAdjustment: Bool { sourceRaw == Self.balanceAdjustmentSource }

  /// Imported from SimpleFIN or a bank file.
  var isFromBank: Bool { sourceRaw == "simplefin" || sourceRaw == "bankFile" }

  init(
    accountID: UUID,
    transferAccountID: UUID? = nil,
    envelopeID: UUID? = nil,
    date: Date,
    amountMinor: Int64,
    payee: String,
    merchantDomain: String? = nil,
    notes: String,
    kind: BudgetTransactionKind
  ) {
    self.accountID = accountID
    self.transferAccountID = transferAccountID
    self.envelopeID = envelopeID
    self.date = date
    self.amountMinor = amountMinor
    self.payee = payee
    self.merchantDomain = merchantDomain
    self.notes = notes
    self.kindRaw = kind.rawValue
  }
}
