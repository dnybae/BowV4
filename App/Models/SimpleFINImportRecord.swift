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
}

enum SimpleFINImportStatus: String {
  case review
  case linked
  case imported
  case ignored
}
