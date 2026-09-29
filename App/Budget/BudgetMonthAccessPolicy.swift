import Foundation

struct BudgetMonthAccessPolicy {
  var calendar: Calendar = .current

  func canAdvance(from viewedMonth: Date, today: Date, assignedMinor: Int64) -> Bool {
    let viewed = calendar.dateInterval(of: .month, for: viewedMonth)?.start ?? viewedMonth
    let current = calendar.dateInterval(of: .month, for: today)?.start ?? today
    return viewed < current || assignedMinor > 0
  }

  func assignedMinor(in month: Date, funding: [BudgetMonthFundingItem]) -> Int64 {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
    return funding.reduce(Int64(0)) { total, item in
      guard interval.contains(item.date) else { return total }
      if !item.hasSource && item.hasTarget { return total + item.amountMinor }
      if item.hasSource && !item.hasTarget { return total - item.amountMinor }
      return total
    }
  }

  func lastAccessibleMonth(today: Date, funding: [BudgetMonthFundingItem]) -> Date {
    var month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    for _ in 0...funding.count {
      guard assignedMinor(in: month, funding: funding) > 0,
            let next = calendar.date(byAdding: .month, value: 1, to: month) else {
        return month
      }
      month = next
    }
    return month
  }
}

struct BudgetMonthFundingItem {
  var date: Date
  var amountMinor: Int64
  var hasSource: Bool
  var hasTarget: Bool
}
