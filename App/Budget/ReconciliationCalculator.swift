import Foundation

struct ReconciliationEntry: Identifiable, Sendable {
  var id: UUID
  var date: Date
  var amountMinor: Int64
  var isCleared: Bool
}

struct ReconciliationLedgerItem: Sendable {
  var id: UUID
  var date: Date
  var amountMinor: Int64
  var accountID: UUID
  var transferAccountID: UUID?
  var isCleared: Bool
  var destinationIsCleared: Bool
}

struct ReconciliationCalculator {
  var calendar: Calendar = .current

  func entries(accountID: UUID, transactions: [ReconciliationLedgerItem], through date: Date) -> [ReconciliationEntry] {
    let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    return transactions.compactMap { transaction in
      guard transaction.date < nextDay else { return nil }
      if transaction.accountID == accountID {
        return ReconciliationEntry(id: transaction.id, date: transaction.date, amountMinor: transaction.amountMinor, isCleared: transaction.isCleared)
      }
      if transaction.transferAccountID == accountID {
        return ReconciliationEntry(id: transaction.id, date: transaction.date, amountMinor: -transaction.amountMinor, isCleared: transaction.destinationIsCleared)
      }
      return nil
    }.sorted { $0.date > $1.date }
  }

  func clearedBalance(openingBalanceMinor: Int64, entries: [ReconciliationEntry], selectedIDs: Set<UUID>) -> Int64 {
    entries.filter { selectedIDs.contains($0.id) }
      .reduce(openingBalanceMinor) { $0 + $1.amountMinor }
  }
}
