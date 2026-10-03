import Foundation
import SwiftData

struct ScheduleManagement {
  static func setActive(_ active: Bool, for schedule: BudgetSchedule, in context: ModelContext,
                        now: Date = Date()) throws {
    do {
      if schedule.isActive != active {
        let today = Calendar.current.startOfDay(for: now)
        if active {
          let id = schedule.id
          for occurrence in try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>(
            predicate: #Predicate { $0.scheduleID == id && !$0.isSkipped && $0.scheduledFor <= today }
          )) {
            context.delete(occurrence)
          }
        }
        schedule.reviewedThrough = today
        schedule.isActive = active
      }
      try context.save()
      try? ScheduleTargetSynchronizer().refresh(in: context, today: now)
    } catch { context.rollback(); throw error }
  }
}
