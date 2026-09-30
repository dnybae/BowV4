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
  var originRaw: String = "simplefin"
  var bankStateRaw: String = "posted"
  var isVisiblePending: Bool = false
  var lastSeenAt: Date? = nil
  var matchedAutomatically: Bool = false
  var originalManualSnapshot: Data? = nil
  var date: Date = Date()
  var amountMinor: Int64 = 0
  var payee: String = ""
  var memo: String = ""
  /// The raw `extra` object SimpleFIN sent, kept so future features (like location) can use it.
  var extraJSON: Data? = nil

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

  var origin: BankImportOrigin {
    get { BankImportOrigin(rawValue: originRaw) ?? .simplefin }
    set { originRaw = newValue.rawValue }
  }
}

enum BankImportOrigin: String {
  case simplefin
  case bankFile
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
  var amountMinor: Int64
  var kindRaw: String
  var isCleared: Bool
  var destinationIsCleared: Bool
  var sourceRaw: String
  var externalKey: String?
  var scheduleID: UUID?
  var scheduledFor: Date?

  init(_ transaction: BudgetTransaction) {
    amountMinor = transaction.amountMinor
    kindRaw = transaction.kindRaw
    isCleared = transaction.isCleared
    destinationIsCleared = transaction.destinationIsCleared
    sourceRaw = transaction.sourceRaw
    externalKey = transaction.externalKey
    scheduleID = transaction.scheduleID
    scheduledFor = transaction.scheduledFor
  }
}
