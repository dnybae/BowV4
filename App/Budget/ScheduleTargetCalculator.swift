import Foundation

/// Derives how much scheduled bills add to each envelope's funding target in a given month.
struct ScheduleTargetCalculator {
  var calendar: Calendar = .current

  func contributions(for envelopeID: UUID, schedules: [BudgetSchedule], month: Date) -> [ScheduleTargetContribution] {
    contributions(schedules: schedules.filter { $0.envelopeID == envelopeID }, month: month)
  }

  func totalsByEnvelope(schedules: [BudgetSchedule], month: Date) -> [UUID: Int64] {
    contributions(schedules: schedules, month: month).reduce(into: [:]) { totals, contribution in
      totals[contribution.envelopeID, default: 0] += contribution.totalMinor
    }
  }

  private func contributions(schedules: [BudgetSchedule], month: Date) -> [ScheduleTargetContribution] {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
    let recurrence = ScheduleRecurrence(calendar: calendar)
    var days: [Date] = []
    var day = interval.start
    while day < interval.end {
      days.append(day)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return schedules.compactMap { schedule in
      guard schedule.isActive, schedule.kind != .inflow, let envelopeID = schedule.envelopeID else { return nil }
      let count = days.filter {
        recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: $0)
      }.count
      guard count > 0 else { return nil }
      return ScheduleTargetContribution(
        scheduleID: schedule.id, envelopeID: envelopeID, payee: schedule.payee,
        amountMinor: abs(schedule.amountMinor), occurrences: count
      )
    }
    .sorted { $0.payee.localizedStandardCompare($1.payee) == .orderedAscending }
  }
}

struct ScheduleTargetContribution: Identifiable, Equatable {
  var scheduleID: UUID
  var envelopeID: UUID
  var payee: String
  var amountMinor: Int64
  var occurrences: Int

  var id: UUID { scheduleID }
  var totalMinor: Int64 { amountMinor * Int64(occurrences) }
}
