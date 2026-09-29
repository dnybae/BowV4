import Foundation
import SwiftData

/// Standalone performance fixture. Compile with the model and page repository sources.
/// Pass a row count (default 50,000) to compare several dataset sizes.
@main
struct LargeDataStressChecks {
  static func main() async throws {
    let count = Int(CommandLine.arguments.dropFirst().first ?? "50000") ?? 50_000
    let schema = Schema([
      BudgetTransaction.self, BudgetAccount.self, BudgetEnvelope.self, BudgetAllocation.self
    ])
    let container = try ModelContainer(
      for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let start = Date(timeIntervalSince1970: 1_451_606_400)
    let account = BudgetAccount(
      name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 0
    )
    account.openedAt = CommandLine.arguments.contains("late") ? Date() : start
    let card = BudgetAccount(
      name: "Credit Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: -5_000
    )
    card.openedAt = start
    context.insert(account)
    context.insert(card)
    var envelopes: [BudgetEnvelope] = []
    for index in 0..<100 {
      let envelope = BudgetEnvelope(groupID: UUID(), name: "Envelope \(index)", symbol: "", sortOrder: index)
      context.insert(envelope)
      envelopes.append(envelope)
    }
    try context.save()

    for index in 0..<120 {
      let allocation = BudgetAllocation(
        date: start.addingTimeInterval(TimeInterval(index * 30 * 86_400)),
        amountMinor: 10_000, targetEnvelopeID: envelopes[index % envelopes.count].id
      )
      context.insert(allocation)
    }
    try context.save()

    let generationStart = ContinuousClock.now
    for index in 0..<count {
      let isTransfer = index % 17 == 0
      let onCard = !isTransfer && index % 10 == 0
      let transaction = BudgetTransaction(
        accountID: onCard ? card.id : account.id,
        transferAccountID: isTransfer ? card.id : nil,
        envelopeID: isTransfer ? nil : envelopes[index % envelopes.count].id,
        date: start.addingTimeInterval(TimeInterval(index * 6_300)),
        amountMinor: -Int64(100 + index % 9_900),
        payee: "Payee \(index % 1_000)",
        notes: index % 29 == 0 ? "Searchable note \(index)" : "",
        kind: isTransfer ? .transfer : .expense
      )
      transaction.createdAt = transaction.date.addingTimeInterval(TimeInterval(index % 13))
      context.insert(transaction)
      if index % 500 == 499 { try context.save() }
    }
    try context.save()
    print("seeded \(count) transactions in \(ContinuousClock.now - generationStart)")

    let repository = TransactionPageRepository(modelContainer: container)
    let readStart = ContinuousClock.now
    let first = try await repository.page(.init())
    precondition(first.items.count == min(80, count))
    let second = try await repository.page(.init(offset: first.nextOffset ?? count))
    precondition(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
    let uncategorized = try await repository.countUncategorized()
    precondition(uncategorized == 0)
    print("first two pages in \(ContinuousClock.now - readStart)")

    var filtered = TransactionPageRepository.Request()
    filtered.searchText = "Payee 17"
    let searchStart = ContinuousClock.now
    let searchPage = try await repository.page(filtered)
    precondition(searchPage.items.allSatisfy { $0.payee.localizedCaseInsensitiveContains("Payee 17") })
    print("search page in \(ContinuousClock.now - searchStart)")

    let ledgerStart = ContinuousClock.now
    let readActor = BudgetSnapshotRepository(modelContainer: container)
    func checkParity(month: Date) async throws {
      let checkpoint = try await readActor.snapshot(month: month)
      let original = BudgetLedger.snapshot(
        month: month,
        accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
        envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()),
        allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()),
        transactions: try context.fetch(FetchDescriptor<BudgetTransaction>())
      )
      precondition(checkpoint.readyToAssignMinor == original.readyToAssignMinor)
      precondition(checkpoint.accountBalances == original.accountBalances)
      precondition(checkpoint.cashAvailable == original.cashAvailable)
      precondition(checkpoint.cashShortfall == original.cashShortfall)
      precondition(checkpoint.creditShortfall == original.creditShortfall)
      precondition(checkpoint.paymentAvailable == original.paymentAvailable)
      precondition(checkpoint.assigned == original.assigned)
      precondition(checkpoint.activity == original.activity)
    }
    try await checkParity(month: Date())
    try await checkParity(month: start.addingTimeInterval(3 * 365 * 86_400))
    try await checkParity(month: start.addingTimeInterval(7 * 365 * 86_400))
    let earliest = try context.fetch(FetchDescriptor<BudgetTransaction>(
      sortBy: [SortDescriptor(\.date)]
    )).first
    earliest?.amountMinor -= 25
    try context.save()
    await readActor.invalidate()
    try await checkParity(month: Date())
    print("ledger parity in \(ContinuousClock.now - ledgerStart)")
  }
}
