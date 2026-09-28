import Foundation
import SwiftData

struct ScheduleReviewPlanner {
  var calendar: Calendar = .current

  func refresh(in context: ModelContext, today: Date = Date()) throws {
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let occurrences = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>())
    let transactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let todayStart = calendar.startOfDay(for: today)
    let recurrence = ScheduleRecurrence(calendar: calendar)
    for schedule in schedules where schedule.isActive {
      let firstDay = schedule.reviewedThrough.flatMap {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
      } ?? todayStart
      guard firstDay <= todayStart else { continue }
      var day = firstDay
      while day <= todayStart {
        if recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: day)
          && !occurrences.contains(where: {
            $0.scheduleID == schedule.id && calendar.isDate($0.scheduledFor, inSameDayAs: day)
          })
          && !transactions.contains(where: {
            $0.scheduleID == schedule.id
              && $0.scheduledFor.map { calendar.isDate($0, inSameDayAs: day) } == true
          }) {
          context.insert(BudgetScheduleOccurrence(scheduleID: schedule.id, scheduledFor: day))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
      schedule.reviewedThrough = todayStart
    }
    try context.save()
  }
}
