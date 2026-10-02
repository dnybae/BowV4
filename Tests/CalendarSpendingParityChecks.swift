import Foundation

@main
struct CalendarSpendingParityChecks {
  static func main() {
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 0)
    let day = Calendar.current.startOfDay(for: Date())
    let entered = TransactionListItem(
      id: UUID(), accountID: account.id, date: day, createdAt: day,
      amountMinor: -1200, payee: "Coffee", kindRaw: "expense", sourceRaw: "manual",
      needsApproval: false, accountName: account.name, envelopeName: "Food"
    )
    var categorized = entered
    categorized.envelopeID = UUID()
    categorized.sourceRaw = "manualLinked"
    let pending = SimpleFINImportRecord(remoteKey: "pending", localAccountID: account.id,
      date: day, amountMinor: -1200, payee: "Coffee")
    pending.bankState = .pending
    pending.isVisiblePending = true
    pending.transactionID = entered.id
    let review = SimpleFINImportRecord(remoteKey: "review", localAccountID: account.id,
      date: day, amountMinor: -500, payee: "Shop")
    let unentered = SimpleFINImportRecord(remoteKey: "unentered", localAccountID: account.id,
      date: day, amountMinor: -300, payee: "Bakery")
    unentered.bankState = .pending
    unentered.isVisiblePending = true
    let records = [pending, review, unentered]
    let inbox = ReviewInbox(transactions: [], records: records, occurrences: [], schedules: [])
    let timeline = SpendingTimeline(transactions: [categorized], reviewTransactions: [],
      inbox: inbox, records: records, accounts: [account], envelopes: [],
      currencyCode: "USD", searchText: "", filter: TransactionFilter())
    let rows = timeline.days.flatMap(\.items)
    precondition(rows.count == 3, "Entered pending items must not duplicate the ledger row")
    precondition(rows.first?.status == .bankReview, "Review rows sort first on both screens")
    let enteredRow = TransactionRowModel(rows.first { $0.id == "transaction-\(entered.id)" }!)
    precondition(enteredRow.isMatched, "Both calendar and spending retain the matched indicator")
    precondition(enteredRow.state == .normal && enteredRow.amountSymbol == "clock")
    let pendingRow = TransactionRowModel(rows.first { $0.id == "pending-\(unentered.id)" }!)
    precondition(pendingRow.state == .pending("Pending") && pendingRow.amountSymbol == "clock")
    var filter = TransactionFilter()
    filter.startDate = Calendar.current.date(byAdding: .month, value: 1, to: day)
    let outside = SpendingTimeline(transactions: [], reviewTransactions: [], inbox: inbox,
      records: records, accounts: [account], envelopes: [], currencyCode: "USD",
      searchText: "", filter: filter)
    precondition(outside.isEmpty, "Bank items outside the selected calendar month must stay hidden")
    print("Calendar/Spending parity checks passed")
  }
}
