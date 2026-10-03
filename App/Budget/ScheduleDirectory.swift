import Foundation
import SwiftData

/// One row per schedule: its oldest outstanding due date, or its next future date.
struct ScheduleDirectory {
  var calendar = Calendar.current

  func recordedDates(in context: ModelContext) throws -> Set<ScheduleDateKey> {
    var request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.scheduleID != nil && $0.scheduledFor != nil
    })
    request.propertiesToFetch = [\.scheduleID, \.scheduledFor]
    return Set(try context.fetch(request).compactMap { transaction in
      guard let id = transaction.scheduleID, let date = transaction.scheduledFor else { return nil }
      return ScheduleDateKey(scheduleID: id, date: calendar.startOfDay(for: date))
    })
  }

  func items(
    schedules: [BudgetSchedule], occurrences: [BudgetScheduleOccurrence],
    recorded: Set<ScheduleDateKey>, now: Date = Date()
  ) -> [ScheduleDirectoryItem] {
    let today = calendar.startOfDay(for: now)
    let excluded = recorded.union(occurrences.filter(\.isSkipped).map {
      ScheduleDateKey(scheduleID: $0.scheduleID, date: calendar.startOfDay(for: $0.scheduledFor))
    })
    let recurrence = ScheduleRecurrence(calendar: calendar)
    return schedules.compactMap { schedule in
      if !schedule.isActive {
        if schedule.frequency == .once,
           excluded.contains(.init(scheduleID: schedule.id, date: calendar.startOfDay(for: schedule.startDate))) {
          return nil
        }
        return ScheduleDirectoryItem(schedule: schedule, date: nil, needsAttention: false)
      }
      let due = occurrences.filter {
        $0.scheduleID == schedule.id && !$0.isSkipped && $0.scheduledFor <= today
          && !excluded.contains(.init(scheduleID: schedule.id, date: calendar.startOfDay(for: $0.scheduledFor)))
      }.map(\.scheduledFor).min()
      if let due { return ScheduleDirectoryItem(schedule: schedule, date: due, needsAttention: true) }
      // A one-time item can still need attention before the first refresh creates its occurrence.
      if schedule.frequency == .once {
        let date = calendar.startOfDay(for: schedule.startDate)
        guard !excluded.contains(.init(scheduleID: schedule.id, date: date)) else { return nil }
        return ScheduleDirectoryItem(schedule: schedule, date: date, needsAttention: date <= today)
      }
      guard var earliest = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
      for _ in 0...excluded.count {
        guard let date = recurrence.nextDate(starting: schedule.startDate, frequency: schedule.frequency,
                                             onOrAfter: earliest) else { return nil }
        if excluded.contains(.init(scheduleID: schedule.id, date: date)) {
          guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
          earliest = next
          continue
        }
        return ScheduleDirectoryItem(schedule: schedule, date: date, needsAttention: false)
      }
      return nil
    }.sorted {
      if $0.schedule.isActive != $1.schedule.isActive { return $0.schedule.isActive }
      if $0.needsAttention != $1.needsAttention { return $0.needsAttention }
      if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
      return $0.schedule.payee.localizedStandardCompare($1.schedule.payee) == .orderedAscending
    }
  }
}

struct ScheduleDateKey: Hashable {
  var scheduleID: UUID
  var date: Date
}

struct ScheduleDirectoryItem: Identifiable {
  var schedule: BudgetSchedule
  var date: Date?
  var needsAttention: Bool
  var id: UUID { schedule.id }

  var frequencyLabel: String { schedule.frequency == .once ? "One-time" : schedule.frequency.title }

  var statusLabel: String {
    guard schedule.isActive, let date else { return "Paused · \(frequencyLabel)" }
    let formatted = date.formatted(.dateTime.month(.abbreviated).day().year())
    return "\(needsAttention ? "Due" : "Next") \(formatted) · \(frequencyLabel)"
  }
}
