import Foundation

@main
struct CalendarTimelineWindowChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.firstWeekday = 1

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    var window = CalendarTimelineWindow(centeredOn: date(2026, 9, 29), calendar: calendar)
    let september30 = date(2026, 9, 30)
    let october1 = date(2026, 10, 1)
    let septemberIndex = window.days.firstIndex { $0.date == september30 }!
    let octoberIndex = window.days.firstIndex { $0.date == october1 }!
    assert(octoberIndex == septemberIndex + 1, "Month boundaries must share a week without padding")

    func checkAlignment(_ window: CalendarTimelineWindow) {
      let dates = window.days.compactMap(\.date)
      assert(Set(dates).count == dates.count, "Every date must appear once")
      for (index, slot) in window.days.enumerated() {
        guard let day = slot.date else { continue }
        let weekdayColumn = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        assert(index % 7 == weekdayColumn, "Each date must stay in its weekday column")
        assert(day == calendar.startOfDay(for: day), "Dates must match normalized transaction days")
      }
      for (previous, next) in zip(dates, dates.dropFirst()) {
        assert(calendar.dateComponents([.day], from: previous, to: next).day == 1)
      }
    }

    checkAlignment(window)
    for _ in 0..<4 {
      window.extend(.earlier)
      checkAlignment(window)
      assert(calendar.dateComponents([.month], from: window.firstMonth, to: window.endMonth).month == 19)
    }
    for _ in 0..<8 {
      window.extend(.later)
      checkAlignment(window)
      assert(calendar.dateComponents([.month], from: window.firstMonth, to: window.endMonth).month == 19)
    }
    print("Calendar timeline window checks passed")
  }
}
