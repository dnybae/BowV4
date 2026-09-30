import Foundation

/// A compact summary of how often and how much a person pays (or is paid by) one payee.
struct PayeeActivity: Sendable {
  enum Direction: Sendable {
    case spending, income
  }

  struct Record: Sendable {
    var date: Date
    var amountMinor: Int64
    var accountID: UUID
    var kind: BudgetTransactionKind
  }

  struct Month: Identifiable, Sendable {
    var start: Date
    var totalMinor: Int64

    var id: Date { start }
  }

  var direction: Direction
  var yearToDateMinor: Int64
  var averageMinor: Int64
  var transactionCount: Int
  /// Payments in the last 12 months, or since the first one if more recent.
  var recentCount: Int
  var recentMonthSpan: Int
  var months: [Month]
  var usualAccountID: UUID?

  var yearToDateTitle: String {
    direction == .spending ? "Spent this year" : "Received this year"
  }

  /// A plain-language cadence such as "About 3× a month", or nil when there's too little history.
  var frequencyDescription: String? {
    guard recentCount >= 3, recentMonthSpan > 0 else { return nil }
    let perMonth = Double(recentCount) / Double(recentMonthSpan)
    if perMonth >= 0.75 {
      let rounded = max(1, Int(perMonth.rounded()))
      return rounded == 1 ? "About once a month" : "About \(rounded)× a month"
    }
    let perYear = max(1, Int((perMonth * 12).rounded()))
    return perYear == 1 ? "About once a year" : "About \(perYear)× a year"
  }

  static func make(
    from records: [Record], today: Date = Date(), calendar: Calendar = .current
  ) -> PayeeActivity? {
    let expenses = records.filter { $0.kind == .expense }
    let inflows = records.filter { $0.kind == .inflow }
    let direction: Direction = expenses.count >= inflows.count ? .spending : .income
    let relevant = direction == .spending ? expenses : inflows
    guard !relevant.isEmpty else { return nil }

    let total = relevant.reduce(Int64(0)) { $0 + abs($1.amountMinor) }
    let yearStart = calendar.dateInterval(of: .year, for: today)?.start ?? today
    let yearToDate = relevant.filter { $0.date >= yearStart && $0.date <= today }
      .reduce(Int64(0)) { $0 + abs($1.amountMinor) }

    let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
    let monthStarts = (0..<6).reversed().compactMap {
      calendar.date(byAdding: .month, value: -$0, to: currentMonth)
    }
    var monthTotals: [Date: Int64] = [:]
    for record in relevant {
      guard let start = calendar.dateInterval(of: .month, for: record.date)?.start else { continue }
      monthTotals[start, default: 0] += abs(record.amountMinor)
    }
    let months = monthStarts.map { Month(start: $0, totalMinor: monthTotals[$0] ?? 0) }

    let windowStart = calendar.date(byAdding: .month, value: -12, to: today) ?? today
    let recent = relevant.filter { $0.date > windowStart && $0.date <= today }
    let firstRecent = recent.map(\.date).min() ?? today
    let span = calendar.dateComponents([.month], from: firstRecent, to: today).month ?? 0

    var accountCounts: [UUID: Int] = [:]
    for record in recent { accountCounts[record.accountID, default: 0] += 1 }
    let usualAccount = accountCounts.max { $0.value < $1.value }
    let usualAccountID = recent.count >= 2 && (usualAccount?.value ?? 0) * 2 > recent.count
      ? usualAccount?.key : nil

    return PayeeActivity(
      direction: direction,
      yearToDateMinor: yearToDate,
      averageMinor: total / Int64(relevant.count),
      transactionCount: relevant.count,
      recentCount: recent.count,
      recentMonthSpan: min(12, max(1, span + 1)),
      months: months,
      usualAccountID: usualAccountID
    )
  }
}
