import Foundation

@main
struct ScheduleTargetCalculatorChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let calculator = ScheduleTargetCalculator(calendar: calendar)
    func day(_ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    let bills = UUID()
    let groceries = UUID()
    func schedule(_ amount: Int64, _ envelope: UUID?, _ start: Date, _ frequency: ScheduleFrequency,
                  kind: BudgetTransactionKind = .expense) -> BudgetSchedule {
      BudgetSchedule(payee: "Bill", amountMinor: amount, accountID: nil, envelopeID: envelope,
                     startDate: start, frequency: frequency, notes: "", kind: kind)
    }

    let twoMonthly = [schedule(5_000, bills, day(1, 5), .monthly), schedule(5_000, bills, day(1, 20), .monthly)]
    expect(calculator.totalsByEnvelope(schedules: twoMonthly, month: day(9, 1))[bills] == 10_000,
           "two $50 monthly bills make a $100 target")

    // September 2026 has four Thursdays; October has five.
    let weekly = [schedule(13_000, groceries, day(9, 3), .weekly)]
    expect(calculator.totalsByEnvelope(schedules: weekly, month: day(9, 1))[groceries] == 52_000,
           "weekly bills count four occurrences in September")
    expect(calculator.totalsByEnvelope(schedules: weekly, month: day(10, 1))[groceries] == 65_000,
           "weekly bills count five occurrences in October")
    expect(calculator.contributions(for: groceries, schedules: weekly, month: day(10, 1)).first?.occurrences == 5,
           "contributions report occurrence counts")

    let midMonthStart = [schedule(10_000, groceries, day(9, 17), .weekly)]
    expect(calculator.totalsByEnvelope(schedules: midMonthStart, month: day(9, 1))[groceries] == 20_000,
           "occurrences before the start date are skipped")

    let yearly = [schedule(12_000, bills, day(3, 18), .yearly)]
    expect(calculator.totalsByEnvelope(schedules: yearly, month: day(9, 1))[bills] == nil,
           "yearly bills only count in their due month")
    expect(calculator.totalsByEnvelope(schedules: yearly, month: day(3, 1))[bills] == 12_000,
           "yearly bills count fully in their due month")

    let once = [schedule(28_000, bills, day(9, 29), .once)]
    expect(calculator.totalsByEnvelope(schedules: once, month: day(9, 1))[bills] == 28_000,
           "one-time bills count in their month")

    let paused = schedule(5_000, bills, day(1, 5), .monthly)
    paused.isActive = false
    let excluded = [paused, schedule(90_000, bills, day(1, 1), .monthly, kind: .inflow),
                    schedule(5_000, nil, day(1, 5), .monthly)]
    expect(calculator.totalsByEnvelope(schedules: excluded, month: day(9, 1)).isEmpty,
           "paused, inflow, and unassigned schedules are ignored")

    let moved = schedule(5_000, bills, day(1, 5), .monthly)
    moved.envelopeID = groceries
    let totals = calculator.totalsByEnvelope(schedules: [moved], month: day(9, 1))
    expect(totals[bills] == nil && totals[groceries] == 5_000, "moving a bill moves its target")

    print("Schedule target checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    if !condition {
      print("FAILED: \(message)")
      exit(1)
    }
  }
}
