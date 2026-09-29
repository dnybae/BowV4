import Foundation
import SwiftData

struct ScheduleReviewPlanner {
  var calendar: Calendar = .current

  func refresh(in context: ModelContext, today: Date = Date()) throws {
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let occurrences = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>())
    let todayStart = calendar.startOfDay(for: today)
    let recurrence = ScheduleRecurrence(calendar: calendar)
    let active = schedules.filter(\.isActive)
    let firstDays = active.map { schedule in
      schedule.reviewedThrough.flatMap {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
      } ?? todayStart
    }
    guard let earliest = firstDays.min(), earliest <= todayStart else { return }
    let end = calendar.date(byAdding: .day, value: 1, to: todayStart)
      ?? todayStart.addingTimeInterval(86_400)
    var recordedRequest = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.scheduleID != nil && $0.scheduledFor != nil
        && $0.scheduledFor! >= earliest && $0.scheduledFor! < end
    })
    recordedRequest.propertiesToFetch = [\.id, \.scheduleID, \.scheduledFor]
    let recorded = try context.fetch(recordedRequest)
    let recordedKeys = Set(recorded.compactMap { transaction -> ScheduleOccurrenceKey? in
      guard let scheduleID = transaction.scheduleID,
            let scheduledFor = transaction.scheduledFor else { return nil }
      return ScheduleOccurrenceKey(scheduleID: scheduleID, day: calendar.startOfDay(for: scheduledFor))
    })
    var occurrenceKeys = Set(occurrences.map {
      ScheduleOccurrenceKey(scheduleID: $0.scheduleID, day: calendar.startOfDay(for: $0.scheduledFor))
    })
    for (schedule, firstDay) in zip(active, firstDays) {
      guard firstDay <= todayStart else { continue }
      var day = firstDay
      while day <= todayStart {
        let key = ScheduleOccurrenceKey(scheduleID: schedule.id, day: day)
        if recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: day)
          && !occurrenceKeys.contains(key) && !recordedKeys.contains(key) {
          context.insert(BudgetScheduleOccurrence(scheduleID: schedule.id, scheduledFor: day))
          occurrenceKeys.insert(key)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
      schedule.reviewedThrough = todayStart
    }
    try context.save()
  }
}

private struct ScheduleOccurrenceKey: Hashable {
  var scheduleID: UUID
  var day: Date
}
