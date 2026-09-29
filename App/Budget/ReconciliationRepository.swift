import Foundation
import SwiftData

struct ReconciliationRead: Sendable {
  var entries: [ReconciliationEntry]
  var payeeNames: [UUID: String]
}

@ModelActor
actor ReconciliationRepository {
  func load(accountID: UUID, through date: Date) throws -> ReconciliationRead {
    let end = Calendar.current.date(byAdding: .day, value: 1,
      to: Calendar.current.startOfDay(for: date)) ?? date
    var result = ReconciliationRead(entries: [], payeeNames: [:])
    var offset = 0
    while true {
      try Task.checkCancellation()
      var request = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate {
          $0.date < end && ($0.accountID == accountID || $0.transferAccountID == accountID)
        }, sortBy: [SortDescriptor(\.date, order: .reverse),
                   SortDescriptor(\.id, order: .reverse)]
      )
      request.fetchLimit = 512
      request.fetchOffset = offset
      request.propertiesToFetch = [\.id, \.date, \.amountMinor, \.accountID,
                                   \.transferAccountID, \.isCleared,
                                   \.destinationIsCleared, \.payee]
      let batch = try ModelContext(modelContainer).fetch(request)
      for transaction in batch {
        let isSource = transaction.accountID == accountID
        result.entries.append(ReconciliationEntry(
          id: transaction.id, date: transaction.date,
          amountMinor: isSource ? transaction.amountMinor : -transaction.amountMinor,
          isCleared: isSource ? transaction.isCleared : transaction.destinationIsCleared
        ))
        result.payeeNames[transaction.id] = transaction.payee
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    return result
  }

  func finish(
    accountID: UUID, through date: Date,
    balanceMinor: Int64, selectedIDs: Set<UUID>
  ) throws {
    let end = Calendar.current.date(byAdding: .day, value: 1,
      to: Calendar.current.startOfDay(for: date)) ?? date
    let reconciledAt = Date()
    var offset = 0
    while true {
      try Task.checkCancellation()
      let context = ModelContext(modelContainer)
      var request = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate {
          $0.date < end && ($0.accountID == accountID || $0.transferAccountID == accountID)
        }, sortBy: [SortDescriptor(\.id)]
      )
      request.fetchLimit = 512
      request.fetchOffset = offset
      let batch = try context.fetch(request)
      for transaction in batch {
        let selected = selectedIDs.contains(transaction.id)
        if transaction.accountID == accountID {
          transaction.isCleared = selected
          transaction.reconciledAt = selected ? reconciledAt : nil
        } else {
          transaction.destinationIsCleared = selected
          transaction.destinationReconciledAt = selected ? reconciledAt : nil
        }
      }
      if context.hasChanges { try context.save() }
      offset += batch.count
      if batch.count < 512 { break }
    }
    let context = ModelContext(modelContainer)
    var request = FetchDescriptor<BudgetAccount>(predicate: #Predicate { $0.id == accountID })
    request.fetchLimit = 1
    guard let account = try context.fetch(request).first else { return }
    account.lastReconciledAt = date
    account.lastReconciledBalanceMinor = balanceMinor
    try context.save()
  }
}
