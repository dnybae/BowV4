import Foundation
import SwiftData

@Model
final class SimpleFINConnection {
  var id: UUID = UUID()
  var lastAttemptAt: Date? = nil
  var lastSuccessfulAt: Date? = nil
  var lastMappingChangeAt: Date? = nil
  var quotaWindowStartedAt: Date? = nil
  var requestsInWindow: Int = 0
  var lastMessage: String? = nil
  var automaticSync: Bool = true

  init() {}
}
