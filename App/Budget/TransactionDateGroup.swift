import Foundation

struct TransactionDateGroup: Identifiable {
  var day: Date
  var items: [TransactionListItem]
  var title: String

  var id: Date { day }

  static func make(
    _ items: [TransactionListItem],
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> [TransactionDateGroup] {
    let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
    return byDay.keys.sorted(by: >).map { day in
      let title: String
      if calendar.isDate(day, inSameDayAs: now) {
        title = "Today"
      } else if calendar.isDate(day, inSameDayAs:
        calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
        title = "Yesterday"
      } else {
        title = day.formatted(date: .complete, time: .omitted)
      }
      return TransactionDateGroup(day: day, items: byDay[day] ?? [], title: title)
    }
  }
}
