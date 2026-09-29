import Foundation

@main
struct BudgetMonthAccessPolicyChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func month(_ number: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: number, day: 1))!
    }
    let policy = BudgetMonthAccessPolicy(calendar: calendar)
    let september = month(9)
    let october = month(10)
    let november = month(11)
    let septemberFunding = BudgetMonthFundingItem(
      date: september, amountMinor: 10_000, hasSource: false, hasTarget: true
    )
    let octoberMove = BudgetMonthFundingItem(
      date: october, amountMinor: 5_000, hasSource: true, hasTarget: true
    )
    let octoberFunding = BudgetMonthFundingItem(
      date: october, amountMinor: 2_000, hasSource: false, hasTarget: true
    )

    expect(policy.canAdvance(from: month(8), today: september, assignedMinor: 0),
           "past months remain navigable")
    expect(!policy.canAdvance(from: september, today: september, assignedMinor: 0),
           "an unfunded current month does not open the future")
    expect(policy.lastAccessibleMonth(today: september, funding: [septemberFunding]) == october,
           "funding opens exactly one future month")
    expect(policy.assignedMinor(in: october, funding: [octoberMove]) == 0,
           "moving between funded buckets does not unlock another month")
    expect(policy.lastAccessibleMonth(today: september,
                                      funding: [septemberFunding, octoberMove]) == october,
           "an internal move cannot open November")
    expect(policy.lastAccessibleMonth(today: september,
                                      funding: [septemberFunding, octoberFunding]) == november,
           "funding October opens November")
    let returnToReady = BudgetMonthFundingItem(
      date: october, amountMinor: 2_000, hasSource: true, hasTarget: false
    )
    expect(policy.assignedMinor(in: october,
                                funding: [octoberFunding, returnToReady]) == 0,
           "returning all funding closes the next month")
    print("Budget month access policy checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
