import Foundation
import SwiftData

/// Changes that can be taken back from their toast's Undo button.
@MainActor
enum UndoableChanges {
  /// Deletes a transaction. One you entered yourself, with no bill or bank item behind it, can be
  /// put back exactly; the others change more than the transaction, so they have no undo.
  static func delete(_ transaction: BudgetTransaction, in context: ModelContext) throws -> (@MainActor () -> Void)? {
    let restorable = transaction.sourceRaw == "manual" && transaction.scheduleID == nil
    let copy = BowBackup.Transaction(transaction)
    try BudgetCommands.deleteTransaction(transaction, in: context)
    guard restorable else { return nil }
    return {
      context.insert(copy.model)
      try? context.save()
    }
  }

  /// Takes back a money move by removing the allocation it recorded.
  static func undoMove(_ allocation: BudgetAllocation, in context: ModelContext) -> @MainActor () -> Void {
    let id = allocation.id
    return {
      let request = FetchDescriptor<BudgetAllocation>(predicate: #Predicate { $0.id == id })
      for item in (try? context.fetch(request)) ?? [] { context.delete(item) }
      try? context.save()
    }
  }
}
