import Foundation

/// A credit card payoff goal, like YNAB's: either a fixed amount each month, or a payoff date
/// from which Bow works out the monthly amount.
///
/// With a date, the debt still to fund is spread evenly over the months left, this one included,
/// so the amount falls if you pay extra and rises if you fall behind.
struct CardPayoffPlanner {
  var calendar: Calendar = .current

  /// What to fund this month toward the goal, or nil without a goal.
  func monthlyMinor(debtMinor: Int64, monthlyTargetMinor: Int64?, goalDate: Date?, month: Date) -> Int64? {
    if let goalDate {
      let debt = max(0, debtMinor)
      guard debt > 0 else { return 0 }
      let months = Int64(EnvelopeTargetPlanner(calendar: calendar).monthsLeft(from: month, through: goalDate))
      return (debt + months - 1) / months
    }
    return monthlyTargetMinor
  }

  /// The month the debt is paid off at a fixed monthly amount; nil if it never would be.
  func payoffMonth(debtMinor: Int64, monthlyMinor: Int64, from month: Date) -> Date? {
    guard monthlyMinor > 0 else { return nil }
    let months = max(1, Int((max(0, debtMinor) + monthlyMinor - 1) / monthlyMinor))
    return calendar.date(byAdding: .month, value: months - 1, to: month)
  }
}
