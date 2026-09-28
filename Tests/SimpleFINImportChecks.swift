import Foundation
import SwiftData

@main
struct SimpleFINImportChecks {
  @MainActor
  static func main() throws {
    let container = try ModelContainer(
      for: BudgetAccount.self, BudgetTransaction.self, SimpleFINAccountLink.self,
      SimpleFINImportRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000)
    account.openedAt = date.addingTimeInterval(-30 * 86_400)
    context.insert(account)
    let link = SimpleFINAccountLink(remoteKey: "connection|bank-account", name: "Bank Checking", currencyCode: "USD")
    link.localAccountID = account.id
    context.insert(link)

    let manual = BudgetTransaction(
      accountID: account.id, date: date, amountMinor: -2_548,
      payee: "Corner Café", notes: "Lunch budget", kind: .expense
    )
    let uncertain = BudgetTransaction(
      accountID: account.id, date: date, amountMinor: -500,
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
    precondition(first.imported == 1 && first.linked == 1 && first.needsReview == 1)
    precondition(manual.notes == "Lunch budget" && manual.isCleared && manual.needsApproval)
    let firstTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let firstRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(firstTransactions.count == 3)
    precondition(firstRecords.count == 3)

    let repeated = try coordinator.importTransactions([remote], in: context)
    precondition(repeated.imported == 0 && repeated.linked == 0 && repeated.needsReview == 0)
    let review = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
      .first { $0.status == .review }!
    let currentTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let currentRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(coordinator.possibleMatches(
      for: review, among: currentTransactions, records: currentRecords
    ).contains { $0.id == uncertain.id })
    try coordinator.resolve(review, as: .link(uncertain.id), in: context)
    precondition(review.status == .linked && uncertain.notes == "Keep this"
      && uncertain.amountMinor == -550)
    let finalTransactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    precondition(finalTransactions.count == 3)
    print("SimpleFIN import checks passed")
  }
}
