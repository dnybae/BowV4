import Foundation
import SwiftData

@Model
final class BudgetScheduleOccurrence {
  var id: UUID = UUID()
  var scheduleID: UUID = UUID()
  var scheduledFor: Date = Date()
  var isSkipped: Bool = false

  init(scheduleID: UUID, scheduledFor: Date) {
    self.scheduleID = scheduleID
    self.scheduledFor = scheduledFor
  }
}
