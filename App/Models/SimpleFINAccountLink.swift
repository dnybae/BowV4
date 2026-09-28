import Foundation
import SwiftData

@Model
final class SimpleFINAccountLink {
  var id: UUID = UUID()
  var remoteKey: String = ""
  var name: String = ""
  var currencyCode: String = "USD"
  var localAccountID: UUID? = nil
  var reportedBalance: String? = nil
  var reportedAt: Date? = nil

  init(remoteKey: String, name: String, currencyCode: String) {
    self.remoteKey = remoteKey
    self.name = name
    self.currencyCode = currencyCode
  }
}
