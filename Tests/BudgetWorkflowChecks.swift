import Foundation
import SwiftData

@MainActor
@main
struct BudgetWorkflowChecks {
  static func main() throws {
    let schema = Schema([
      BudgetAccount.self, BudgetGroup.self, BudgetEnvelope.self,
      BudgetAllocation.self, BudgetTransaction.self, BudgetSchedule.self,
      BudgetScheduleOccurrence.self, BudgetPayee.self, SimpleFINImportRecord.self
    ])
    let container = try ModelContainer(
      for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let now = Date()
    let group = BudgetGroup(name: "Needs", sortOrder: 0)
    let food = BudgetEnvelope(groupID: group.id, name: "Food", symbol: "", sortOrder: 0)
    let travel = BudgetEnvelope(groupID: group.id, name: "Travel", symbol: "", sortOrder: 1)
    let checking = BudgetAccount(
      name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000
    )
    let card = BudgetAccount(
      name: "Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: -5_000
    )
    let extraCard = BudgetAccount(
      name: "Extra", kind: .credit, currencyCode: "USD", openingBalanceMinor: 0
    )
    for account in [checking, card, extraCard] {
      account.openedAt = now.addingTimeInterval(-86_400)
      context.insert(account)
    }
    context.insert(group)
    context.insert(food)
    context.insert(travel)
    try context.save()

    func snapshot() throws -> BudgetSnapshot {
      BudgetLedger.snapshot(
        month: now,
        accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
        envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
        allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()),
        transactions: try context.fetch(FetchDescriptor<BudgetTransaction>())
      )
    }
    func summary() throws -> BudgetSummary {
      BudgetSummary(
        snapshot: try snapshot(),
        envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
        accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
        allocations: try context.fetch(FetchDescriptor<BudgetAllocation>())
      )
    }

    try BudgetCommands.moveMoney(
      amountMinor: 6_000, from: .readyToAssign, to: .envelope(food.id),
      date: now, in: context
    )
    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .envelope(food.id), to: .envelope(travel.id),
      date: now, in: context
    )
    let afterAssignments = try summary()
    precondition(afterAssignments.readyToAssignMinor == 4_000)
    precondition(afterAssignments.assignedThisMonthMinor == 6_000,
                 "moving between envelopes must not double-count assigned money")
    do {
      try BudgetCommands.moveMoney(
        amountMinor: 5_000, from: .readyToAssign, to: .envelope(food.id),
        date: now, in: context
      )
      preconditionFailure("the command must check current funds")
    } catch BudgetCommandError.insufficientFunds {
      // Expected.
    }

    let groceries = BudgetTransaction(
      accountID: checking.id, envelopeID: food.id, date: now,
      amountMinor: -2_000, payee: "Groceries", notes: "", kind: .expense
    )
    context.insert(groceries)
    try context.save()
    let afterGroceries = try summary()
    let afterGroceriesSnapshot = try snapshot()
    precondition(afterGroceries.readyToAssignMinor == 4_000,
                 "funded cash spending must not change Ready to Assign")
    precondition(afterGroceriesSnapshot.available(for: food.id) == 3_000)

    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .readyToAssign, to: .cardPayment(card.id),
      date: now, in: context
    )
    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .readyToAssign, to: .cardPayment(extraCard.id),
      date: now, in: context
    )
    let afterCardAssignments = try summary()
    precondition(afterCardAssignments.creditUncoveredMinor == 4_000,
                 "excess on one card cannot conceal another card's shortfall")
    try BudgetCommands.setEnvelopeHidden(food, hidden: true, in: context)
    let afterHide = try snapshot()
    precondition(afterHide.available(for: food.id) == 3_000,
                 "hiding must preserve envelope funds")
    do {
      try BudgetCommands.deleteUnusedEnvelope(food, in: context)
      preconditionFailure("an envelope with history must not be deleted")
    } catch BudgetCommandError.envelopeHasHistory {
      // Expected.
    }

    let due = BudgetSchedule(
      payee: "Gym", amountMinor: 500, accountID: checking.id,
      envelopeID: travel.id, startDate: now, frequency: .once, notes: ""
    )
    context.insert(due)
    try context.save()
    try ScheduleReviewPlanner().refresh(in: context, today: now)
    try ScheduleReviewPlanner().refresh(in: context, today: now)
    let occurrences = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>())
    precondition(occurrences.count == 1, "repeated refresh must not duplicate occurrences")
    let beforeRecord = try snapshot()
    let inbox = ReviewInbox(
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()),
      records: [], occurrences: occurrences, schedules: [due]
    )
    precondition(inbox.items.count == 1)
    let bankRecord = SimpleFINImportRecord(
      remoteKey: "gym-posted", localAccountID: checking.id,
      date: now, amountMinor: -500, payee: "Gym"
    )
    let groupedInbox = ReviewInbox(
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()),
      records: [bankRecord], occurrences: occurrences, schedules: [due]
    )
    precondition(groupedInbox.items.count == 1,
                 "an exact bank and schedule match should have one review action")
    let afterDue = try snapshot()
    precondition(afterDue.readyToAssignMinor == beforeRecord.readyToAssignMinor,
                 "unrecorded schedules must not affect the ledger")

    try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: travel.id,
      amountMinor: 500, date: now, payee: "Gym", notes: "",
      scheduleID: due.id, scheduledFor: now, in: context
    )
    let afterRecord = ReviewInbox(
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()),
      records: [], occurrences: occurrences, schedules: [due]
    )
    precondition(afterRecord.items.isEmpty, "recording resolves the due occurrence")
    do {
      try BudgetCommands.addTransaction(
        kind: .expense, account: checking, destination: nil, envelopeID: travel.id,
        amountMinor: 500, date: now, payee: "Gym", notes: "",
        scheduleID: due.id, scheduledFor: now, in: context
      )
      preconditionFailure("the same occurrence cannot be recorded twice")
    } catch BudgetCommandError.duplicateScheduledOccurrence {
      // Expected.
    }
    print("Budget workflow checks passed")
  }
}
