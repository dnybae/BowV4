import Foundation
import SwiftData

@MainActor
@main
struct OverspendingCoverChecks {
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
    let groceries = BudgetEnvelope(groupID: group.id, name: "Groceries", symbol: "", sortOrder: 0)
    let dining = BudgetEnvelope(groupID: group.id, name: "Dining", symbol: "", sortOrder: 1)
    let attire = BudgetEnvelope(groupID: group.id, name: "Attire", symbol: "", sortOrder: 2)
    let books = BudgetEnvelope(groupID: group.id, name: "Books", symbol: "", sortOrder: 3)
    let checking = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000)
    let card = BudgetAccount(name: "Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: 0)
    for account in [checking, card] {
      account.openedAt = now.addingTimeInterval(-86_400)
      context.insert(account)
    }
    context.insert(group)
    for envelope in [groceries, dining, attire, books] { context.insert(envelope) }
    try context.save()
    try BudgetCommands.ensureCardPaymentEnvelopes(in: context)

    func snapshot() throws -> BudgetSnapshot {
      BudgetLedger.snapshot(
        month: now,
        accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
        envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
        allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()),
        transactions: try context.fetch(FetchDescriptor<BudgetTransaction>())
      )
    }
    func overspending(cardID: UUID? = nil) throws -> OverspendingSummary {
      OverspendingSummary(
        snapshot: try snapshot(), envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
        groups: [group], cardID: cardID
      )
    }
    let date = BudgetCommands.allocationDate(inMonth: now)

    // Fund donors, then overspend Groceries with cash and Dining on the card.
    try BudgetCommands.moveMoney(amountMinor: 1_961, from: .readyToAssign, to: .envelope(attire.id),
                                 date: date, snapshot: try snapshot(), in: context)
    try BudgetCommands.moveMoney(amountMinor: 1_000, from: .readyToAssign, to: .envelope(books.id),
                                 date: date, snapshot: try snapshot(), in: context)
    try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: groceries.id,
      amountMinor: 1_000, date: now, payee: "Market", notes: "", in: context
    )
    try BudgetCommands.addTransaction(
      kind: .expense, account: card, destination: nil, envelopeID: dining.id,
      amountMinor: 2_500, date: now, payee: "Bistro", notes: "", in: context
    )

    var summary = try overspending()
    expect(summary.items.map(\.envelopeID) == [groceries.id, dining.id], "overspent envelopes follow budget order")
    expect(summary.totalMinor == 3_500 && summary.cashMinor == 1_000 && summary.creditMinor == 2_500,
           "overspending splits into cash and credit")
    expect(summary.creditMinor(onCard: card.id) == 2_500, "credit overspending is attributed to its card")
    expect(try overspending(cardID: card.id).items.map(\.envelopeID) == [dining.id],
           "filtering by card keeps only envelopes overspent on that card")

    // Rejections leave nothing behind.
    func rejects(_ donors: [BudgetBucket: Int64], for envelopeID: UUID, _ message: String) throws {
      let allocationCount = try context.fetchCount(FetchDescriptor<BudgetAllocation>())
      do {
        try BudgetCommands.coverOverspending(envelopeID: envelopeID, from: donors, date: date,
                                             snapshot: try snapshot(), in: context)
        expect(false, message)
      } catch is BudgetCommandError {
        expect(try context.fetchCount(FetchDescriptor<BudgetAllocation>()) == allocationCount,
               "a rejected cover saves nothing: \(message)")
      }
    }
    try rejects([.envelope(attire.id): 1_000, .envelope(books.id): 1_001], for: groceries.id,
                "a donor can't give more than it has")
    try rejects([.envelope(attire.id): 1_961, .envelope(books.id): 1_000], for: groceries.id,
                "donors can't give more than the envelope is overspent")
    try rejects([.cardPayment(card.id): 100], for: groceries.id, "card payment money isn't a donor")
    try rejects([.envelope(attire.id): 100], for: attire.id, "an envelope can't cover itself")
    try rejects([.envelope(groceries.id): 100], for: attire.id, "only overspent envelopes can be covered")

    // Cash overspending from two donors in one save.
    try BudgetCommands.coverOverspending(
      envelopeID: groceries.id, from: [.envelope(attire.id): 600, .envelope(books.id): 400],
      date: date, snapshot: try snapshot(), in: context
    )
    var current = try snapshot()
    expect(current.available(for: groceries.id) == 0, "two donors bring the envelope back to zero")
    expect(current.available(for: attire.id) == 1_361 && current.available(for: books.id) == 600,
           "each donor gives exactly its amount")

    // Credit overspending: covering it also funds the card payment.
    let paymentBefore = current.paymentAvailable[card.id, default: 0]
    try BudgetCommands.coverOverspending(
      envelopeID: dining.id, from: [.envelope(attire.id): 1_361, .readyToAssign: 1_139],
      date: date, snapshot: current, in: context
    )
    current = try snapshot()
    expect(current.available(for: dining.id) == 0, "Ready to Assign can be a donor")
    expect(current.paymentAvailable[card.id, default: 0] - paymentBefore == 2_500,
           "covering credit overspending moves the money into the card payment")
    expect(try overspending().isEmpty, "nothing is left overspent")
    try rejects([.envelope(books.id): 100], for: dining.id, "a covered envelope can't be covered again")

    print("Overspending cover checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
