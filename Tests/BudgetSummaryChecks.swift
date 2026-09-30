import Foundation
import SwiftData

@MainActor
@main
struct BudgetSummaryChecks {
  static func main() throws {
    let group = BudgetGroup(name: "Essentials", sortOrder: 0)
    let groceries = BudgetEnvelope(groupID: group.id, name: "Groceries", symbol: "", sortOrder: 0)
    let rent = BudgetEnvelope(groupID: group.id, name: "Rent", symbol: "", sortOrder: 1)
    let gifts = BudgetEnvelope(groupID: group.id, name: "Gifts", symbol: "", sortOrder: 2)
    let cardPayment = BudgetEnvelope(groupID: group.id, name: "Card", symbol: "", sortOrder: 3)
    cardPayment.paymentAccountID = UUID()

    let snapshot = BudgetSnapshot(
      month: Date(),
      accountBalances: [:],
      cashAvailable: [groceries.id: 45_320, rent.id: 0, gifts.id: 0, cardPayment.id: 99_900],
      cashShortfall: [gifts.id: 5_800],
      creditShortfall: [:],
      paymentAvailable: [:],
      assigned: [groceries.id: 36_000, rent.id: 145_000],
      activity: [groceries.id: -60_000, rent.id: -145_000, gifts.id: 3_000, cardPayment.id: -50_000],
      readyToAssignMinor: 1_281_380,
      cashTotalMinor: 0
    )
    let summary = BudgetSummary(
      snapshot: snapshot, envelopes: [groceries, rent, gifts, cardPayment],
      accounts: [], allocations: []
    )
    expect(summary.spentThisMonthMinor == 202_000, "spent nets refunds and skips card payment envelopes")
    expect(summary.availableMinor == 45_320, "available counts only money left in budget envelopes")
    expect(summary.overspentMinor == 5_800, "overspent still tracks shortfalls separately")

    expect(BudgetSummary.assignedShare(assignedMinor: 335_000, readyToAssignMinor: 1_281_380) > 0.2,
           "share of cash with a job uses assigned ÷ (assigned + Ready to Assign)")
    expect(BudgetSummary.assignedShare(assignedMinor: 335_000, readyToAssignMinor: 1_281_380) < 0.21,
           "share stays below 21% for the demo numbers")
    expect(BudgetSummary.assignedShare(assignedMinor: 0, readyToAssignMinor: 0) == 0, "nothing assigned is 0%")
    expect(BudgetSummary.assignedShare(assignedMinor: 500, readyToAssignMinor: 0) == 1, "fully assigned is 100%")
    expect(BudgetSummary.assignedShare(assignedMinor: 500, readyToAssignMinor: -800) == 1,
           "over-assigned cash is capped at 100%")
    print("Budget summary checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
