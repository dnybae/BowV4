import Foundation

enum ScheduleFrequency: String, CaseIterable, Identifiable {
  case once
  case weekly
  case monthly
  case yearly

  var id: String { rawValue }

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
