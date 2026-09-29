import Foundation

struct CalendarMonthPage {
  var start: Date
  var end: Date
  var days: [CalendarMonthDay]
  var calendar: Calendar

  init(containing date: Date, calendar: Calendar = .current) {
    self.calendar = calendar
    start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    end = calendar.date(byAdding: .month, value: 1, to: start) ?? start

    let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    var slots = (0..<leading).map { CalendarMonthDay(id: .blank($0), date: nil) }
    let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
    for offset in 0..<dayCount {
      guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
      let day = calendar.startOfDay(for: date)
      slots.append(CalendarMonthDay(id: .day(day), date: day))
    }
    let trailing = (7 - slots.count % 7) % 7
    let firstTrailingIndex = slots.count
    slots += (0..<trailing).map { CalendarMonthDay(id: .blank(firstTrailingIndex + $0), date: nil) }
    days = slots
  }

  func adjacentSelection(from selectedDate: Date, by months: Int) -> Date? {
    guard let targetMonth = calendar.date(byAdding: .month, value: months, to: start),
          let dayCount = calendar.range(of: .day, in: .month, for: targetMonth)?.count else {
      return nil
    }
    let selectedDay = min(calendar.component(.day, from: selectedDate), dayCount)
    guard let date = calendar.date(byAdding: .day, value: selectedDay - 1, to: targetMonth) else {
      return nil
    }
    return calendar.startOfDay(for: date)
  }
}

struct CalendarMonthDay: Identifiable {
  enum ID: Hashable {
    case blank(Int)
    case day(Date)
  }

  var id: ID
  var date: Date?
}
