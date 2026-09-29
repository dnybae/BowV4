import Foundation

struct EnvelopeFundingAdvisor {
  var calendar: Calendar = .current

  func suggestedMonthlyMinor(envelopeID: UUID, transactions: [BudgetTransaction], asOf date: Date = Date()) -> Int64? {
    let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
    let relevant = transactions.filter { $0.envelopeID == envelopeID && $0.date < currentMonth }
    guard let firstDate = relevant.map(\.date).min(),
          let firstMonth = calendar.dateInterval(of: .month, for: firstDate)?.start else { return nil }
    let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: currentMonth) ?? firstMonth
    let start = max(firstMonth, sixMonthsAgo)
    let count = max(1, calendar.dateComponents([.month], from: start, to: currentMonth).month ?? 1)
    let netSpent = relevant.filter { $0.date >= start }.reduce(Int64(0)) { $0 - $1.amountMinor }
    guard netSpent > 0 else { return nil }
    return Int64((Double(netSpent) / Double(count)).rounded(.up))
  }
}
