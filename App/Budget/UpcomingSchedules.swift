import Foundation

/// The next date each active schedule is due, for the Upcoming rows on a detail screen.
///
/// Bills enter themselves on their date, so only days after today count as upcoming.
/// Each schedule appears once, which keeps every recurring bill reachable from the screen.
struct UpcomingSchedules {
  var calendar: Calendar = .current
  /// How far ahead to look for a yearly bill's next date.
  var horizonDays = 400

  func items(
    for schedules: [BudgetSchedule], skipped: [BudgetScheduleOccurrence], after now: Date = Date()
  ) -> [UpcomingSchedule] {
    let recurrence = ScheduleRecurrence(calendar: calendar)
    let skippedDays = Set(skipped.filter(\.isSkipped).map {
      UpcomingSchedule.Key(scheduleID: $0.scheduleID, day: calendar.startOfDay(for: $0.scheduledFor))
    })
    let today = calendar.startOfDay(for: now)
    return schedules.compactMap { schedule in
      guard schedule.isActive else { return nil }
      for offset in 1...horizonDays {
        guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
        guard recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: day),
              !skippedDays.contains(.init(scheduleID: schedule.id, day: day)) else { continue }
        return UpcomingSchedule(
          scheduleID: schedule.id, date: day, payee: schedule.payee, kind: schedule.kind,
          frequency: schedule.frequency,
          amountMinor: schedule.kind == .inflow ? abs(schedule.amountMinor) : -abs(schedule.amountMinor)
        )
      }
      return nil
    }
    .sorted { $0.date == $1.date ? $0.payee < $1.payee : $0.date < $1.date }
  }
}

struct UpcomingSchedule: Identifiable, Equatable {
  struct Key: Hashable {
    var scheduleID: UUID
    var day: Date
  }

  var scheduleID: UUID
  var date: Date
  var payee: String
  var kind: BudgetTransactionKind
  var frequency: ScheduleFrequency
  /// Signed like a transaction: negative for money going out.
  var amountMinor: Int64

  var id: UUID { scheduleID }

  /// "Monthly · Oct 15": how often, then the next date.
  var statusLabel: String {
    let date = date.formatted(.dateTime.month(.abbreviated).day())
    return frequency == .once ? "Scheduled · \(date)" : "\(frequency.title) · \(date)"
  }

  /// The same row the Spending screen draws for a scheduled bill.
  func rowModel(accountName: String, envelopeName: String?) -> TransactionRowModel {
    TransactionRowModel(
      id: scheduleID.uuidString,
      title: TransactionRowModel.title(payee: payee, kind: kind),
      logoName: kind == .transfer ? "" : payee,
      merchantDomain: nil,
      kind: kind,
      accountName: accountName,
      envelopeName: envelopeName,
      amountMinor: amountMinor,
      state: .scheduled(statusLabel)
    )
  }
}
