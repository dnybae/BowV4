import Foundation

enum ScheduleFrequency: String, CaseIterable, Identifiable {
  case once
  case weekly
  case monthly
  case yearly

  var id: String { rawValue }

  static var recurringCases: [Self] { allCases.filter { $0 != .once } }

  var title: String {
    switch self {
    case .once: "Once"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .yearly: "Yearly"
    }
  }
}

struct ScheduleRecurrence {
  var calendar: Calendar = .current

  /// Finds the next date without a fixed look-ahead window or drifting month-end dates.
  func nextDate(starting startDate: Date, frequency: ScheduleFrequency, onOrAfter date: Date) -> Date? {
    let start = calendar.startOfDay(for: startDate)
    let earliest = max(start, calendar.startOfDay(for: date))
    switch frequency {
    case .once:
      return start >= earliest ? start : nil
    case .weekly:
      let days = calendar.dateComponents([.day], from: start, to: earliest).day ?? 0
      return calendar.date(byAdding: .day, value: ((days + 6) / 7) * 7, to: start)
    case .monthly, .yearly:
      let component: Calendar.Component = frequency == .monthly ? .month : .year
      guard let first = calendar.dateInterval(of: component, for: start)?.start,
            let current = calendar.dateInterval(of: component, for: earliest)?.start else { return nil }
      let distance = calendar.dateComponents([component], from: first, to: current).value(for: component) ?? 0
      for offset in distance...(distance + 1) {
        guard let period = calendar.date(byAdding: component, value: offset, to: first) else { return nil }
        var month = calendar.dateComponents([.era, .year, .month], from: period)
        if frequency == .yearly { month.month = calendar.component(.month, from: start) }
        month.day = 1
        guard let monthStart = calendar.date(from: month),
              let days = calendar.range(of: .day, in: .month, for: monthStart) else { return nil }
        month.day = min(calendar.component(.day, from: start), days.count)
        if let candidate = calendar.date(from: month), candidate >= earliest { return candidate }
      }
      return nil
    }
  }

  func occurs(starting startDate: Date, frequency: ScheduleFrequency, on date: Date) -> Bool {
    let start = calendar.startOfDay(for: startDate)
    let day = calendar.startOfDay(for: date)
    guard day >= start else { return false }
    switch frequency {
    case .once:
      return day == start
    case .weekly:
      let days = calendar.dateComponents([.day], from: start, to: day).day ?? -1
      return days % 7 == 0
    case .monthly:
      let startComponents = calendar.dateComponents([.day], from: start)
      let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
      return calendar.component(.day, from: day) == min(startComponents.day ?? 1, lastDay)
    case .yearly:
      let startComponents = calendar.dateComponents([.month, .day], from: start)
      let month = calendar.component(.month, from: day)
      guard month == startComponents.month else { return false }
      let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
      return calendar.component(.day, from: day) == min(startComponents.day ?? 1, lastDay)
    }
  }
}
