import Foundation

struct CalendarTimelineWindow {
  enum Direction {
    case earlier
    case later
  }

  var firstMonth: Date
  var endMonth: Date
  var days: [CalendarDaySlot]
  var calendar: Calendar

  init(centeredOn date: Date, calendar: Calendar = .current) {
    let month = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    self.calendar = calendar
    firstMonth = calendar.date(byAdding: .month, value: -6, to: month) ?? month
    endMonth = calendar.date(byAdding: .month, value: 7, to: month)
      ?? calendar.date(byAdding: .month, value: 1, to: month)
      ?? month
    days = Self.makeDays(from: firstMonth, to: endMonth, calendar: calendar)
  }

  func contains(_ date: Date) -> Bool {
    date >= firstMonth && date < endMonth
  }

  func directionToExtend(near date: Date) -> Direction? {
    let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
    let before = calendar.dateComponents([.month], from: firstMonth, to: month).month ?? 0
    let after = calendar.dateComponents([.month], from: month, to: endMonth).month ?? 0
    if before <= 2 { return .earlier }
    if after <= 3 { return .later }
    return nil
  }

  mutating func extend(_ direction: Direction) {
    switch direction {
    case .earlier:
      guard let earlier = calendar.date(byAdding: .month, value: -6, to: firstMonth) else { return }
      firstMonth = earlier
      if monthCount > 19,
         let trimmedEnd = calendar.date(byAdding: .month, value: -6, to: endMonth) {
        endMonth = trimmedEnd
      }
    case .later:
      guard let later = calendar.date(byAdding: .month, value: 6, to: endMonth) else { return }
      endMonth = later
      if monthCount > 19,
         let trimmedStart = calendar.date(byAdding: .month, value: 6, to: firstMonth) {
        firstMonth = trimmedStart
      }
    }
    days = Self.makeDays(from: firstMonth, to: endMonth, calendar: calendar)
  }

  private var monthCount: Int {
    calendar.dateComponents([.month], from: firstMonth, to: endMonth).month ?? 0
  }

  private static func makeDays(from start: Date, to end: Date, calendar: Calendar) -> [CalendarDaySlot] {
    guard start < end else { return [] }
    let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    var result = (0..<leading).map { CalendarDaySlot(id: .leading(start, $0), date: nil) }
    var date = start
    while date < end {
      result.append(CalendarDaySlot(id: .day(date), date: date))
      guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
      date = next
    }
    return result
  }
}

struct CalendarDaySlot: Identifiable {
  enum ID: Hashable {
    case leading(Date, Int)
    case day(Date)
  }

  var id: ID
  var date: Date?
}
