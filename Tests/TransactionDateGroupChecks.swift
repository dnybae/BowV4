import Foundation

@main
struct TransactionDateGroupChecks {
  static func main() {
    let calendar = Calendar(identifier: .gregorian)
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 14))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let older = calendar.date(byAdding: .day, value: -4, to: today)!
    func item(_ date: Date, _ payee: String) -> TransactionListItem {
      TransactionListItem(
        id: UUID(), accountID: UUID(), transferAccountID: nil,
        envelopeID: nil, date: date, createdAt: date,
        amountMinor: -100, payee: payee, merchantDomain: nil,
        kindRaw: BudgetTransactionKind.expense.rawValue,
        sourceRaw: "manual", needsApproval: false,
        accountName: "Checking", envelopeName: "Food"
      )
    }
    let results = TransactionDateGroup.make(
      [item(older, "Old"), item(today, "Today one"), item(yesterday, "Yesterday"),
       item(today.addingTimeInterval(-3_600), "Today two")],
      calendar: calendar, now: today
    )
    precondition(results.count == 3)
    precondition(Array(results.map(\.title).prefix(2)) == ["Today", "Yesterday"])
    precondition(results[0].items.count == 2 && results[1].items.count == 1)
    precondition(results[2].items.first?.payee == "Old")
    print("Transaction date group checks passed")
  }
}
