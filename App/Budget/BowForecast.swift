import Foundation

struct BowForecast {
  var calendar: Calendar = .current

  func project(
    from date: Date,
    currentNetWorthMinor: Int64,
    transactions: [BudgetTransaction],
    schedules: [BudgetSchedule],
    months: Int = 6
  ) -> [BowForecastMonth] {
    let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
    let firstHistory = calendar.date(byAdding: .month, value: -3, to: currentMonth) ?? currentMonth
    let recurrence = ScheduleRecurrence(calendar: calendar)
    let actual = transactions.filter { transaction in
      transaction.date >= firstHistory && transaction.date < currentMonth && transaction.scheduleID == nil
        && transaction.sourceRaw != "balanceAdjustment"
        && (transaction.kind == .expense || transaction.kind == .inflow)
        && !schedules.contains(where: { schedule in
          schedule.kind == transaction.kind && schedule.accountID == transaction.accountID
            && schedule.payee.localizedCaseInsensitiveCompare(transaction.payee) == .orderedSame
            && recurrence.occurs(starting: schedule.startDate,
                                 frequency: schedule.frequency, on: transaction.date)
        })
    }
    let historicalChange = actual.reduce(Int64(0)) { $0 + $1.amountMinor }
    let baseline = historicalChange / 3
    var balance = currentNetWorthMinor
    var result: [BowForecastMonth] = []
    for offset in 1...max(1, months) {
      guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth),
            let end = calendar.date(byAdding: .month, value: 1, to: month) else { continue }
      var scheduledChange: Int64 = 0
      var day = month
      while day < end {
        for schedule in schedules where schedule.isActive &&
          recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: day) {
          switch schedule.kind {
          case .expense: scheduledChange -= schedule.amountMinor
          case .inflow: scheduledChange += schedule.amountMinor
          case .transfer: break
          }
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
      balance += baseline + scheduledChange
      result.append(BowForecastMonth(month: month, netWorthMinor: balance))
    }
    return result
  }
}

struct BowForecastMonth: Identifiable {
  var month: Date
  var netWorthMinor: Int64
  var id: Date { month }
}
