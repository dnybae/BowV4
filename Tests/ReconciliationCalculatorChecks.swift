import Foundation

@main
struct ReconciliationCalculatorChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
    let cash = UUID()
    let credit = UUID()
    let expense = ReconciliationLedgerItem(id: UUID(), date: day, amountMinor: -2_500, accountID: cash, transferAccountID: nil, isCleared: true, destinationIsCleared: false)
    let payment = ReconciliationLedgerItem(id: UUID(), date: day, amountMinor: -3_000, accountID: cash, transferAccountID: credit, isCleared: true, destinationIsCleared: false)
    let pending = ReconciliationLedgerItem(id: UUID(), date: tomorrow, amountMinor: -1_000, accountID: cash, transferAccountID: nil, isCleared: false, destinationIsCleared: false)
    let calculator = ReconciliationCalculator(calendar: calendar)
    let cashEntries = calculator.entries(accountID: cash, transactions: [expense, payment, pending], through: day)
    assert(cashEntries.count == 2)
    assert(calculator.clearedBalance(openingBalanceMinor: 10_000, entries: cashEntries, selectedIDs: Set(cashEntries.filter(\.isCleared).map(\.id))) == 4_500)
    let creditEntries = calculator.entries(accountID: credit, transactions: [expense, payment, pending], through: day)
    assert(creditEntries.count == 1 && creditEntries[0].amountMinor == 3_000)
    assert(!creditEntries[0].isCleared)
    print("Reconciliation calculator checks passed")
  }
}
