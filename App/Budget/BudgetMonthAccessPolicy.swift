import Foundation

struct BudgetMonthAccessPolicy {
  var calendar: Calendar = .current

  func canAdvance(from viewedMonth: Date, today: Date, assignedMinor: Int64) -> Bool {
    let viewed = calendar.dateInterval(of: .month, for: viewedMonth)?.start ?? viewedMonth
    let current = calendar.dateInterval(of: .month, for: today)?.start ?? today
    return viewed < current || assignedMinor > 0
  }

  func assignedMinor(in month: Date, allocations: [BudgetAllocation]) -> Int64 {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
    return allocations.reduce(Int64(0)) { total, allocation in
      guard interval.contains(allocation.date) else { return total }
      let hasSource = allocation.sourceEnvelopeID != nil || allocation.sourceCardID != nil
      let hasTarget = allocation.targetEnvelopeID != nil || allocation.targetCardID != nil
      if !hasSource && hasTarget { return total + allocation.amountMinor }
      if hasSource && !hasTarget { return total - allocation.amountMinor }
      return total
    }
  }

  func lastAccessibleMonth(today: Date, allocations: [BudgetAllocation]) -> Date {
    var month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    for _ in 0...allocations.count {
      guard assignedMinor(in: month, allocations: allocations) > 0,
            let next = calendar.date(byAdding: .month, value: 1, to: month) else {
        return month
      }
      month = next
    }
    return month
  }
}
