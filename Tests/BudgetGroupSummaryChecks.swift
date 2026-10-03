import Foundation
import SwiftData

@MainActor
@main
struct BudgetGroupSummaryChecks {
  static func main() {
    let mixed = BudgetGroupSummary(items: [
      envelope(available: 100_000, assigned: 100_000, target: nil),
      envelope(available: -12_000, assigned: 0, target: 20_000),
      envelope(available: 8_000, assigned: 8_000, target: 15_000),
      envelope(available: 0, assigned: 0, target: nil)
    ])
    expect(mixed.availableMinor == 96_000, "combined availability includes shortfalls")
    expect(mixed.count == 4, "the summary counts every visible item")
    expect(mixed.overspentCount == 1 && mixed.needsFundingCount == 1,
           "positive totals keep both overspending and target shortfalls visible")
    expect(mixed.fundedCount == 1 && mixed.emptyCount == 1, "mixed states are counted independently")
    expect(mixed.needsAttention, "a positive net balance cannot mark a mixed group as funded")

    let spentTarget = envelope(available: 0, assigned: 20_000, target: 20_000)
    let fullyAssigned = BudgetGroupSummary(items: [spentTarget, envelope(available: 5_000, assigned: 5_000, target: 5_000)])
    expect(!fullyAssigned.needsAttention, "spending a fully assigned target does not create a new funding need")
    expect(fullyAssigned.emptyCount == 1 && fullyAssigned.fundedCount == 1, "spent targets follow the individual row's state")
    let unassigned = BudgetGroupSummary(items: [envelope(available: 0, assigned: 0, target: 5_000)])
    expect(unassigned.needsFundingCount == 1 && unassigned.emptyCount == 0, "an empty envelope with an unmet target needs funding")

    let cards = BudgetGroupSummary(items: [
      payment(owed: 40_000, reserved: 20_000, carryingDebt: true),
      payment(owed: 25_000, reserved: 10_000, carryingDebt: false),
      payment(owed: 15_000, reserved: 15_000, carryingDebt: false)
    ])
    expect(cards.availableMinor == 45_000, "card groups total payment money set aside")
    expect(cards.overspentCount == 1 && cards.needsFundingCount == 1 && cards.fundedCount == 1,
           "carried debt and new unfunded credit spending remain distinct")

    let empty = BudgetGroupSummary(items: [])
    expect(empty.count == 0 && empty.availableMinor == 0 && !empty.needsAttention, "empty groups have no warnings")
    let negative = BudgetGroupSummary(items: [envelope(available: -8_000, assigned: 0, target: nil)])
    expect(negative.availableMinor == -8_000 && negative.overspentCount == 1, "negative totals retain their sign")

    let checking = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 0)
    let savings = BudgetAccount(name: "Savings", kind: .cash, currencyCode: "USD", openingBalanceMinor: 0)
    let card = BudgetAccount(name: "Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: 0)
    let balanceSummary = AccountGroupSummary(
      accounts: [checking, savings, card],
      balances: [checking.id: 30_000, savings.id: 50_000, card.id: -10_000],
      linkedAccountIDs: [checking.id, UUID()]
    )
    expect(balanceSummary.balanceMinor == 70_000, "account totals use signed ledger balances")
    expect(balanceSummary.linkedCount == 1 && balanceSummary.manualCount == 2,
           "links outside the group do not affect linked or manual counts")
    let creditSummary = AccountGroupSummary(accounts: [card], balances: [card.id: -10_000], linkedAccountIDs: [])
    expect(creditSummary.balanceMinor == -10_000 && creditSummary.manualCount == 1,
           "credit debt is a normal signed balance, independent of update status")
    print("Budget group summary checks passed")
  }

  private static func envelope(available: Int64, assigned: Int64, target: Int64?) -> BudgetGroupSummary.Item {
    BudgetGroupSummary.Item(
      availableMinor: available,
      status: EnvelopeStatus(availableMinor: available, assignedMinor: assigned, activityMinor: 0,
                             monthlyTargetMinor: target, currencyCode: "USD")
    )
  }

  private static func payment(owed: Int64, reserved: Int64, carryingDebt: Bool) -> BudgetGroupSummary.Item {
    BudgetGroupSummary.Item(
      availableMinor: reserved,
      status: EnvelopeStatus(cardOwedMinor: owed, reservedMinor: reserved,
                             isCarryingDebt: carryingDebt, currencyCode: "USD")
    )
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
