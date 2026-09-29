import Foundation
import SwiftData

@Model
final class SimpleFINImportRecord {
  #Index<SimpleFINImportRecord>([\.id], [\.remoteKey], [\.transactionID], [\.statusRaw, \.date])
  var id: UUID = UUID()
  var remoteKey: String = ""
  var localAccountID: UUID = UUID()
  var transactionID: UUID? = nil
  var statusRaw: String = "review"
  var bankStateRaw: String = "posted"
  var isVisiblePending: Bool = false
  var lastSeenAt: Date? = nil
  var matchedAutomatically: Bool = false
  var originalManualSnapshot: Data? = nil
  var pendingEnteredAt: Date? = nil
  var date: Date = Date()
  var amountMinor: Int64 = 0
  var payee: String = ""

  init(remoteKey: String, localAccountID: UUID, date: Date, amountMinor: Int64, payee: String) {
    self.remoteKey = remoteKey
    self.localAccountID = localAccountID
    self.date = date
    self.amountMinor = amountMinor
    self.payee = payee
  }

  var status: SimpleFINImportStatus {
    get { SimpleFINImportStatus(rawValue: statusRaw) ?? .review }
    set { statusRaw = newValue.rawValue }
  }

  var bankState: ImportedBankState {
    get { ImportedBankState(rawValue: bankStateRaw) ?? .posted }
    set { bankStateRaw = newValue.rawValue }
  }
}

enum ImportedBankState: String {
  case pending
  case posted
}

enum SimpleFINImportStatus: String {
  case review
  case linked
  case imported
  case ignored
}

struct ManualTransactionSnapshot: Codable {
  var accountID: UUID
  var transferAccountID: UUID?
  var envelopeID: UUID?
  var date: Date
  var amountMinor: Int64
  var payee: String
  var notes: String
  var kindRaw: String
  var isCleared: Bool
  var destinationIsCleared: Bool
  var sourceRaw: String
  var externalKey: String?
  var needsApproval: Bool
  var scheduleID: UUID?
  var scheduledFor: Date?

  init(_ transaction: BudgetTransaction) {
    accountID = transaction.accountID
    transferAccountID = transaction.transferAccountID
    envelopeID = transaction.envelopeID
    date = transaction.date
    amountMinor = transaction.amountMinor
    payee = transaction.payee
    notes = transaction.notes
    kindRaw = transaction.kindRaw
    isCleared = transaction.isCleared
    destinationIsCleared = transaction.destinationIsCleared
    sourceRaw = transaction.sourceRaw
    externalKey = transaction.externalKey
    needsApproval = transaction.needsApproval
    scheduleID = transaction.scheduleID
    scheduledFor = transaction.scheduledFor
  }

  func restore(_ transaction: BudgetTransaction) {
    transaction.accountID = accountID
    transaction.transferAccountID = transferAccountID
    transaction.envelopeID = envelopeID
    transaction.date = date
    transaction.amountMinor = amountMinor
    transaction.payee = payee
    transaction.notes = notes
    transaction.kindRaw = kindRaw
    transaction.isCleared = isCleared
    transaction.destinationIsCleared = destinationIsCleared
    transaction.sourceRaw = sourceRaw
    transaction.externalKey = externalKey
    transaction.needsApproval = needsApproval
    transaction.scheduleID = scheduleID
    transaction.scheduledFor = scheduledFor
  }
}
