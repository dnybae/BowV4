import Foundation

@main
struct ScheduleRecurrenceChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let recurrence = ScheduleRecurrence(calendar: calendar)
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    assert(recurrence.occurs(starting: date(2026, 1, 31), frequency: .monthly, on: date(2026, 2, 28)))
    assert(recurrence.occurs(starting: date(2026, 1, 31), frequency: .monthly, on: date(2026, 3, 31)))
    assert(!recurrence.occurs(starting: date(2026, 1, 31), frequency: .monthly, on: date(2026, 2, 27)))
    assert(recurrence.occurs(starting: date(2024, 2, 29), frequency: .yearly, on: date(2025, 2, 28)))
    assert(recurrence.occurs(starting: date(2026, 9, 1), frequency: .weekly, on: date(2026, 9, 29)))
    assert(!recurrence.occurs(starting: date(2026, 9, 1), frequency: .weekly, on: date(2026, 9, 30)))
    assert(!recurrence.occurs(starting: date(2026, 9, 1), frequency: .once, on: date(2026, 10, 1)))
    print("Schedule recurrence checks passed")
  }
}
