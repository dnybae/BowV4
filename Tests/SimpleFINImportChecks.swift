import Foundation
import SwiftData

@main
struct SimpleFINImportChecks {
  @MainActor
  static func main() throws {
    let container = try ModelContainer(
      for: BudgetAccount.self, BudgetTransaction.self, SimpleFINAccountLink.self,
      SimpleFINImportRecord.self, BudgetEnvelope.self, BudgetGroup.self,
      BudgetSchedule.self, BudgetPayee.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000)
    account.openedAt = date.addingTimeInterval(-30 * 86_400)
    context.insert(account)
    let group = BudgetGroup(name: "Everyday", sortOrder: 0)
    let food = BudgetEnvelope(groupID: group.id, name: "Food", symbol: "cart", sortOrder: 0)
    context.insert(group)
    context.insert(food)
    context.insert(BudgetPayee(name: "Groceries", defaultEnvelopeID: food.id,
                               exactMatchText: "Groceries"))
    let link = SimpleFINAccountLink(remoteKey: "connection|bank-account", name: "Bank Checking", currencyCode: "USD")
    link.localAccountID = account.id
    context.insert(link)

    let manual = BudgetTransaction(
      accountID: account.id, envelopeID: food.id, date: date, amountMinor: -2_548,
      payee: "Corner Café", notes: "Lunch budget", kind: .expense
    )
    let uncertain = BudgetTransaction(
      accountID: account.id, envelopeID: food.id, date: date, amountMinor: -500,
      payee: "Coffee", notes: "Keep this", kind: .expense
    )
    context.insert(manual)
    context.insert(uncertain)
    try context.save()

    let remote = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: [
        SimpleFINRemoteTransaction(id: "matched", posted: date.timeIntervalSince1970,
          amount: "-25.48", description: "Corner Cafe", transactedAt: nil, pending: false),
        SimpleFINRemoteTransaction(id: "new", posted: date.timeIntervalSince1970,
          amount: "-12.75", description: "Groceries", transactedAt: nil, pending: false),
        SimpleFINRemoteTransaction(id: "review", posted: date.timeIntervalSince1970,
          amount: "-5.50", description: "Coffee", transactedAt: nil, pending: false),
        SimpleFINRemoteTransaction(id: "pending", posted: 0,
          amount: "-3.00", description: "Hold", transactedAt: date.timeIntervalSince1970, pending: true)
      ]
    )
    let coordinator = SimpleFINSyncCoordinator.shared
    let first = try coordinator.importTransactions([remote], in: context)
    try context.save()
    precondition(first.linked == 1 && first.imported == 1
      && first.needsReview == 1 && first.pending == 1)
    precondition(manual.notes == "Lunch budget" && manual.isCleared && !manual.needsApproval)
    let firstTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let firstRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(firstTransactions.count == 3, "categorized imports enter the ledger; review and pending stay out")
    precondition(firstRecords.count == 4)
    let pending = firstRecords.first { $0.bankState == .pending }!
    precondition(pending.isVisiblePending && pending.transactionID == nil)
    let inbox = ReviewInbox(transactions: firstTransactions, records: firstRecords,
                            occurrences: [], schedules: [])
    precondition(inbox.bankItems.count == 1 && inbox.scheduledItems.isEmpty)

    let repeated = try coordinator.importTransactions([remote], in: context)
    precondition(repeated.linked == 0
      && repeated.needsReview == 0 && repeated.pending == 0)
    let review = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
      .first { $0.status == .review && $0.payee == "Coffee" }!
    let currentTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let currentRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(coordinator.possibleMatches(
      for: review, among: currentTransactions, records: currentRecords
    ).contains { $0.id == uncertain.id })
    try coordinator.resolve(review, as: .link(uncertain.id), in: context)
    precondition(review.status == .linked && uncertain.notes == "Keep this"
      && uncertain.amountMinor == -550 && !uncertain.needsApproval)
    try coordinator.unmatch(review, in: context)
    precondition(review.status == .review && review.transactionID == nil
      && uncertain.amountMinor == -500 && uncertain.notes == "Keep this"
      && uncertain.sourceRaw == "manual")

    let groceries = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
      .first { $0.payee == "Groceries" }!
    precondition(groceries.status == .imported)
    let imported = try BudgetTransactionLookup.byID(groceries.transactionID!, in: context)!
    precondition(!imported.needsApproval && imported.isCleared)

    try coordinator.enterPending(pending, envelopeID: food.id, in: context)
    let enteredID = pending.transactionID!
    let entered = try BudgetTransactionLookup.byID(enteredID, in: context)!
    precondition(entered.sourceRaw == "manual" && !entered.isCleared)
    let missingPending = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: []
    )
    _ = try coordinator.importTransactions([missingPending], in: context)
    precondition(!pending.isVisiblePending && pending.transactionID == enteredID,
                 "a vanished authorization hides without removing Enter Now")
    let posted = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: [SimpleFINRemoteTransaction(
        id: "pending-posted", posted: date.addingTimeInterval(86_400).timeIntervalSince1970,
        amount: "-3.50", description: "Hold", transactedAt: date.timeIntervalSince1970,
        pending: false
      )]
    )
    let transition = try coordinator.importTransactions([posted], in: context)
    try context.save()
    precondition(transition.needsReview == 1 && !pending.isVisiblePending
      && pending.bankState == .posted && pending.transactionID == nil,
      "changed pending amount becomes one posted review item")
    let countAfterPosting = try context.fetchCount(FetchDescriptor<BudgetTransaction>())
    precondition(countAfterPosting == 4,
                 "the posted update must not duplicate Enter Now")
    try coordinator.resolve(pending, as: .link(enteredID), in: context)
    precondition(pending.status == .linked && entered.amountMinor == -350)
    let countAfterMatching = try context.fetchCount(FetchDescriptor<BudgetTransaction>())
    precondition(countAfterMatching == 4)

    try BudgetCommands.deleteTransaction(imported, in: context)
    precondition(groceries.status == .ignored && groceries.transactionID == nil)
    let finalTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    precondition(finalTransactions.count == 3)

    let savings = BudgetAccount(name: "Savings", kind: .cash, currencyCode: "USD",
                                openingBalanceMinor: 0)
    savings.openedAt = account.openedAt
    context.insert(savings)
    let transfer = BudgetTransaction(
      accountID: account.id, transferAccountID: savings.id, date: date,
      amountMinor: -1_000, payee: "Transfer", notes: "", kind: .transfer
    )
    context.insert(transfer)
    let outgoing = SimpleFINImportRecord(
      remoteKey: "transfer-out", localAccountID: account.id,
      date: date, amountMinor: -1_000, payee: "Transfer"
    )
    let incoming = SimpleFINImportRecord(
      remoteKey: "transfer-in", localAccountID: savings.id,
      date: date, amountMinor: 1_000, payee: "Transfer"
    )
    context.insert(outgoing)
    context.insert(incoming)
    try context.save()
    try coordinator.resolve(outgoing, as: .link(transfer.id), in: context)
    try coordinator.resolve(incoming, as: .link(transfer.id), in: context)
    try coordinator.unmatch(outgoing, in: context)
    precondition(incoming.status == .linked && transfer.destinationIsCleared
      && transfer.sourceRaw == "manualLinked" && transfer.externalKey == "transfer-in",
      "unmatching one transfer leg must retain the other bank link")

    link.importStartDate = date.addingTimeInterval(2 * 86_400)
    let laterActivity = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: [
        SimpleFINRemoteTransaction(
          id: "before-start", posted: date.addingTimeInterval(86_400).timeIntervalSince1970,
          amount: "7.50", description: "Earlier income", transactedAt: nil, pending: false
        ),
        SimpleFINRemoteTransaction(
          id: "after-start", posted: date.addingTimeInterval(3 * 86_400).timeIntervalSince1970,
          amount: "9.00", description: "Later income", transactedAt: nil, pending: false
        )
      ]
    )
    let newOnly = try coordinator.importTransactions([laterActivity], in: context)
    precondition(newOnly.imported == 1)
    let afterStartRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(afterStartRecords.contains { $0.payee == "Later income" })
    precondition(!afterStartRecords.contains { $0.payee == "Earlier income" })
    link.importStartDate = date
    let withHistory = try coordinator.importTransactions([laterActivity], in: context)
    precondition(withHistory.imported == 1,
                 "choosing available history imports older activity once")

    link.importStartDate = date.addingTimeInterval(10 * 86_400)
    let earlierPendingDate = date.addingTimeInterval(9 * 86_400)
    let earlierPending = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: [SimpleFINRemoteTransaction(
        id: "before-start-pending", posted: 0, amount: "-4.30",
        description: "Cutoff Pending", transactedAt: earlierPendingDate.timeIntervalSince1970,
        pending: true
      )]
    )
    let cutoffPendingSummary = try coordinator.importTransactions([earlierPending], in: context)
    precondition(cutoffPendingSummary.pending == 1,
                 "current pending authorizations show even if dated before account setup")
    let earlierPosted = SimpleFINRemoteAccount(
      id: "bank-account", name: "Bank Checking", connID: "connection", currency: "USD",
      transactions: [SimpleFINRemoteTransaction(
        id: "before-start-pending", posted: earlierPendingDate.timeIntervalSince1970,
        amount: "-4.30", description: "Cutoff Pending",
        transactedAt: earlierPendingDate.timeIntervalSince1970, pending: false
      )]
    )
    let cutoffPostedSummary = try coordinator.importTransactions([earlierPosted], in: context)
    let cutoffRecord = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
      .first { $0.payee == "Cutoff Pending" }!
    precondition(cutoffPostedSummary.needsReview == 1 && cutoffRecord.bankState == .posted,
                 "posting a pending item remains reviewable across the import cutoff")
    print("SimpleFIN import checks passed")
  }
}
