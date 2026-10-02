import Foundation
import SwiftData

/// Fetches bank metadata only for transactions still waiting for review. Settled import history
/// stays in the store instead of being materialized by the Spending and Calendar screens.
struct SpendingBankRecordLookup {
  func records(for transactions: [BudgetTransaction], in context: ModelContext) throws -> [SimpleFINImportRecord] {
    let ids = Set(transactions.filter { $0.needsApproval || $0.needsEnvelope }.map(\.id))
    // Equality uses the transactionID index. Coalescing an optional UUID inside an IN
    // predicate compiles, but Core Data cannot translate it to SQL at runtime.
    return try ids.flatMap { id in
      try context.fetch(FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate {
        $0.transactionID == id && $0.statusRaw == "imported" && $0.bankStateRaw == "posted"
      }))
    }
  }
}
