import Foundation

@main
struct PayeeActivityChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
    let card = UUID()
    let debit = UUID()
    func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    let records: [PayeeActivity.Record] = [
      .init(date: day(7, 2), amountMinor: -4_000, accountID: card, kind: .expense),
      .init(date: day(8, 2), amountMinor: -6_000, accountID: card, kind: .expense),
      .init(date: day(9, 2), amountMinor: -5_000, accountID: debit, kind: .expense),
      .init(date: day(12, 20, year: 2025), amountMinor: -3_000, accountID: card, kind: .expense),
      .init(date: day(9, 3), amountMinor: 1_000, accountID: card, kind: .inflow)
    ]
    guard let activity = PayeeActivity.make(from: records, today: today, calendar: calendar) else {
      fatalError("Expected activity")
    }
    precondition(activity.direction == .spending)
    precondition(activity.yearToDateMinor == 15_000)
    precondition(activity.averageMinor == 4_500)
    precondition(activity.transactionCount == 4)
    precondition(activity.usualAccountID == card)
    precondition(activity.months.count == 6)
    precondition(activity.months.last?.totalMinor == 5_000)
    precondition(activity.recentMonthSpan == 10)
    precondition(activity.frequencyDescription == "About 5× a year")

    let monthly = (1...9).map {
      PayeeActivity.Record(date: day($0, 15), amountMinor: -1_599, accountID: card, kind: .expense)
    }
    let subscription = PayeeActivity.make(from: monthly, today: today, calendar: calendar)
    precondition(subscription?.frequencyDescription == "About once a month")

    let paycheck = [PayeeActivity.Record(date: day(9, 1), amountMinor: 200_000, accountID: debit, kind: .inflow)]
    let income = PayeeActivity.make(from: paycheck, today: today, calendar: calendar)
    precondition(income?.direction == .income && income?.frequencyDescription == nil)
    precondition(income?.usualAccountID == nil)
    precondition(PayeeActivity.make(from: [], today: today, calendar: calendar) == nil)
    print("PayeeActivityChecks passed")
  }
}
