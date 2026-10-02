import Foundation

/// What an envelope's target asks you to assign in a month.
///
/// A plain target is the same amount every month. A target with a date is a goal: what's still
/// missing at the start of the month is spread evenly over the months left, this one included,
/// so the monthly amount falls as you get ahead and rises if you fall behind. Scheduled bills
/// for the month add on top either way.
struct EnvelopeTargetPlanner {
  var calendar: Calendar = .current

  func monthlyMinor(
    targetMinor: Int64?, targetDate: Date?, scheduledMinor: Int64,
    carriedInMinor: Int64, month: Date
  ) -> Int64? {
    var total = scheduledMinor
    if let targetMinor, targetMinor > 0 {
      if let targetDate {
        let missing = max(0, targetMinor - max(0, carriedInMinor))
        let months = Int64(monthsLeft(from: month, through: targetDate))
        total += (missing + months - 1) / months
      } else {
        total += targetMinor
      }
    }
    return total > 0 ? total : nil
  }

  /// Months from `month` through the goal's month, counting both; at least one.
  func monthsLeft(from month: Date, through goal: Date) -> Int {
    let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
    let end = calendar.dateInterval(of: .month, for: goal)?.start ?? goal
    let difference = calendar.dateComponents([.month], from: start, to: end).month ?? 0
    return max(1, difference + 1)
  }
}

extension EnvelopeTargetPlanner {
  /// The month's target for `envelope` against a snapshot of that month.
  func monthlyMinor(for envelope: BudgetEnvelope, scheduledMinor: Int64, snapshot: BudgetSnapshot) -> Int64? {
    monthlyMinor(
      targetMinor: envelope.targetMinor, targetDate: envelope.targetDate,
      scheduledMinor: scheduledMinor, carriedInMinor: snapshot.carriedIn(for: envelope.id),
      month: snapshot.month
    )
  }
}
