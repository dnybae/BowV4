import Foundation

/// The date controls recording; recurrence controls whether future dates are planned.
struct TransactionTiming {
  var date: Date
  var isRecurring: Bool
  var frequency: ScheduleFrequency
  var now = Date()
  var calendar = Calendar.current

  var isFuture: Bool {
    calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
  }

  var scheduleFrequency: ScheduleFrequency? {
    if isRecurring { return frequency == .once ? .monthly : frequency }
    return isFuture ? .once : nil
  }

  var explanation: String {
    let formatted = date.formatted(date: .abbreviated, time: .omitted)
    if isFuture {
      return isRecurring
        ? "Scheduled for \(formatted), then repeats \(frequency.title.lowercased())."
        : "Scheduled for \(formatted). Find it in Spending’s scheduled transactions."
    }
    return "Records this transaction and repeats \(frequency.title.lowercased()) from this date. Missed occurrences won’t be added."
  }
}
