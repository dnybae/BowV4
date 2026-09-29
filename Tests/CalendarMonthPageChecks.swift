import Foundation

@main
struct CalendarMonthPageChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.firstWeekday = 1

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    let september = CalendarMonthPage(containing: date(2026, 9, 29), calendar: calendar)
    assert(september.days.count == 35)
    assert(september.days[0].date == nil && september.days[1].date == nil)
    assert(september.days[2].date == date(2026, 9, 1))
    assert(september.days[31].date == date(2026, 9, 30))
    assert(september.days.suffix(3).allSatisfy { $0.date == nil })
    assert(september.days.compactMap(\.date).count == 30, "The grid must contain exactly one month")

    let january = CalendarMonthPage(containing: date(2028, 1, 31), calendar: calendar)
    assert(january.adjacentSelection(from: date(2028, 1, 31), by: 1) == date(2028, 2, 29))
    let february = CalendarMonthPage(containing: date(2028, 2, 29), calendar: calendar)
    assert(february.adjacentSelection(from: date(2028, 2, 29), by: -1) == date(2028, 1, 29))

    for day in september.days.compactMap(\.date) {
      assert(day == calendar.startOfDay(for: day))
    }
    print("Calendar month page checks passed")
  }
}
