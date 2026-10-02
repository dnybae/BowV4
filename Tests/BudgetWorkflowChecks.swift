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
    try BudgetCommands.ensureCardPaymentEnvelopes(in: context)
    try BudgetCommands.ensureCardPaymentEnvelopes(in: context)
    let paymentEnvelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>()).filter { $0.paymentAccountID != nil }
    precondition(paymentEnvelopes.count == 2 && card.paymentEnvelopeID != nil && extraCard.paymentEnvelopeID != nil,
                 "each card has exactly one persistent payment envelope")

    func snapshot(for month: Date = now) throws -> BudgetSnapshot {
      BudgetLedger.snapshot(
        month: month,
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
      date: now, snapshot: try snapshot(), in: context
    )
    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .envelope(food.id), to: .envelope(travel.id),
      date: now, snapshot: try snapshot(), in: context
    )
    let afterAssignments = try summary()
    precondition(afterAssignments.readyToAssignMinor == 4_000)
    precondition(afterAssignments.assignedThisMonthMinor == 6_000,
                 "moving between envelopes must not double-count assigned money")
    do {
      try BudgetCommands.moveMoney(
        amountMinor: 5_000, from: .readyToAssign, to: .envelope(food.id),
        date: now, snapshot: try snapshot(), in: context
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
    do {
      try BudgetCommands.addTransaction(
        kind: .expense, account: checking, destination: nil, envelopeID: nil,
        amountMinor: 100, date: now, payee: "Missing envelope", notes: "", in: context
      )
      preconditionFailure("manual expenses must require an envelope")
    } catch BudgetCommandError.expenseNeedsEnvelope {
      // Expected.
    }
    let afterGroceries = try summary()
    let afterGroceriesSnapshot = try snapshot()
    precondition(afterGroceries.readyToAssignMinor == 4_000,
                 "funded cash spending must not change Ready to Assign")
    precondition(afterGroceriesSnapshot.available(for: food.id) == 3_000)

    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .readyToAssign, to: .cardPayment(card.id),
      date: now, snapshot: try snapshot(), in: context
    )
    try BudgetCommands.moveMoney(
      amountMinor: 1_000, from: .readyToAssign, to: .cardPayment(extraCard.id),
      date: now, snapshot: try snapshot(), in: context
    )
    let afterCardAssignments = try summary()
    precondition(afterCardAssignments.creditUncoveredMinor == 4_000,
                 "excess on one card cannot conceal another card's shortfall")
    try BudgetCommands.setEnvelopeHidden(
      food, hidden: true, availableMinor: try snapshot().available(for: food.id), in: context
    )
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
    // A bill with an account and envelope enters itself on its due date.
    let entered = try context.fetch(FetchDescriptor<BudgetTransaction>()).filter { $0.scheduleID == due.id }
    precondition(entered.count == 1 && entered[0].envelopeID == travel.id,
                 "a due bill is entered once, like a transaction you entered")
    let afterRecord = ReviewInbox(
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()),
      records: [], occurrences: occurrences, schedules: [due]
    )
    precondition(afterRecord.items.isEmpty, "an entered bill leaves nothing to review")
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
    let beforeFuture = try snapshot()
    let futureMonth = Calendar.current.date(byAdding: .month, value: 1,
      to: Calendar.current.dateInterval(of: .month, for: now)!.start)!
    try BudgetCommands.moveMoney(amountMinor: 500, from: .readyToAssign,
      to: .envelope(travel.id), date: futureMonth, snapshot: try snapshot(for: futureMonth), in: context)
    let currentAfterFuture = try snapshot()
    let futureSnapshot = BudgetLedger.snapshot(month: futureMonth,
      accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
      envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
      allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()),
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()))
    precondition(currentAfterFuture.readyToAssignMinor == beforeFuture.readyToAssignMinor - 500,
      "future funding reserves Ready to Assign now")
    precondition(futureSnapshot.available(for: travel.id) == beforeFuture.available(for: travel.id) + 500,
      "future month can be funded")
    let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: now)!
    do {
      try BudgetCommands.moveMoney(amountMinor: 100, from: .readyToAssign,
        to: .envelope(travel.id), date: previousMonth, snapshot: try snapshot(for: previousMonth), in: context)
      preconditionFailure("past budget months must be read only")
    } catch BudgetCommandError.pastMonthLocked {
      // Expected.
    }
    print("Budget workflow checks passed")
  }
}
