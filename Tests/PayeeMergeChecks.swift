import Foundation
import SwiftData

@main
struct PayeeMergeChecks {
  static func main() async throws {
    let container = try ModelContainer(
      for: BudgetPayee.self, BudgetTransaction.self, BudgetSchedule.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let groceries = UUID()
    let account = UUID()
    let target = BudgetPayee(name: "Target", merchantDomain: "target.com")
    target.bankNames = ["TARGET T-1234"]
    let duplicate = BudgetPayee(name: "Target.com", defaultEnvelopeID: groceries, exactMatchText: "TARGET.COM *ORDER")
    duplicate.notes = "Order pickup account"
    context.insert(target)
    context.insert(duplicate)
    for payee in ["Target", "Target.com", "TARGET.COM *ORDER", "Other Store"] {
      context.insert(BudgetTransaction(
        accountID: account, date: Date(), amountMinor: -1_000, payee: payee, notes: "", kind: .expense
      ))
    }
    context.insert(BudgetSchedule(
      payee: "Target.com", amountMinor: 1_000, accountID: account, envelopeID: groceries,
      startDate: Date(), frequency: .monthly, notes: ""
    ))
    try context.save()

    let repository = PayeeDirectoryRepository(modelContainer: container)
    try await repository.merge(
      sourceKey: PayeeDirectory.key("Target.com"), sourceName: "Target.com",
      into: PayeeDirectory.key("Target"), targetName: "Target"
    )

    let check = ModelContext(container)
    let payees = try check.fetch(FetchDescriptor<BudgetPayee>())
    precondition(payees.count == 1, "duplicate payee is removed")
    let merged = payees[0]
    precondition(merged.name == "Target")
    precondition(merged.bankNames == ["TARGET T-1234", "Target.com", "TARGET.COM *ORDER"])
    precondition(merged.defaultEnvelopeID == groceries, "missing default envelope carries over")
    precondition(merged.notes == "Order pickup account")
    precondition(merged.merchantDomain == "target.com", "target keeps its own website")

    let names = try check.fetch(FetchDescriptor<BudgetTransaction>()).map(\.payee).sorted()
    precondition(names == ["Other Store", "TARGET.COM *ORDER", "Target", "Target"],
                 "duplicate's own name moves, raw bank text stays for matching")
    let schedules = try check.fetch(FetchDescriptor<BudgetSchedule>())
    precondition(schedules.first?.payee == "Target")

    let entries = try await repository.entries()
    let targetEntry = entries.first { $0.key == PayeeDirectory.key("Target") }
    precondition(entries.count == 2 && targetEntry?.transactionCount == 3 && targetEntry?.scheduleCount == 1)

    let activity = try await repository.activity(for: PayeeDirectory.key("Target"))
    precondition(activity?.transactionCount == 3)
    let lastUsed = try await repository.lastUsed(payee: "TARGET.COM *ORDER", kind: .expense)
    precondition(lastUsed?.accountID == account)
    print("PayeeMergeChecks passed")
  }
}
