import Foundation

@main
struct PayeeRecurrenceChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
    let card = UUID()
    let envelope = UUID()
    func day(_ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    func charge(_ date: Date, _ minor: Int64) -> PayeeActivity.Record {
      .init(date: date, amountMinor: -minor, accountID: card, kind: .expense, envelopeID: envelope)
    }

    // Monthly subscription with a price increase.
    let subscription = [
      charge(day(6, 14), 1_399), charge(day(7, 14), 1_399),
      charge(day(8, 14), 1_599), charge(day(9, 14), 1_599)
    ]
    let monthly = PayeeRecurrence.detect(in: subscription, today: today, calendar: calendar)
    precondition(monthly?.frequency == .monthly)
    precondition(monthly?.amountMinor == 1_599)
    precondition(monthly?.previousAmountMinor == nil, "latest two charges match")
    precondition(monthly?.nextDate == day(10, 14))
    precondition(monthly?.accountID == card && monthly?.envelopeID == envelope)

    let justIncreased = [charge(day(7, 14), 1_399), charge(day(8, 14), 1_399), charge(day(9, 14), 1_599)]
    precondition(PayeeRecurrence.detect(in: justIncreased, today: today, calendar: calendar)?
      .previousAmountMinor == 1_399)

    // Weekly charge.
    let weekly = [charge(day(9, 9), 500), charge(day(9, 16), 500), charge(day(9, 23), 520)]
    let weeklyResult = PayeeRecurrence.detect(in: weekly, today: today, calendar: calendar)
    precondition(weeklyResult?.frequency == .weekly)
    precondition(weeklyResult?.nextDate == day(9, 30))

    // Too few charges, irregular spacing, wildly different amounts, or stopped.
    precondition(PayeeRecurrence.detect(in: Array(subscription.prefix(2)), today: today, calendar: calendar) == nil)
    let irregular = [charge(day(6, 1), 1_000), charge(day(6, 20), 1_000), charge(day(9, 1), 1_000)]
    precondition(PayeeRecurrence.detect(in: irregular, today: today, calendar: calendar) == nil)
    let groceries = [charge(day(7, 1), 2_000), charge(day(8, 1), 9_000), charge(day(9, 1), 4_000)]
    precondition(PayeeRecurrence.detect(in: groceries, today: today, calendar: calendar) == nil)
    let cancelled = [charge(day(4, 1), 999), charge(day(5, 1), 999), charge(day(6, 1), 999)]
    precondition(PayeeRecurrence.detect(in: cancelled, today: today, calendar: calendar) == nil)

    // Activity only suggests recurrence for spending.
    let activity = PayeeActivity.make(from: subscription, today: today, calendar: calendar)
    precondition(activity?.recurrence?.frequency == .monthly)
    print("PayeeRecurrenceChecks passed")
  }
}
