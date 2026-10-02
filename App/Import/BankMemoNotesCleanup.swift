import Foundation
import SwiftData

/// Bow used to copy a bank's memo into a transaction's Notes. Notes are only for what you type,
/// so this clears, once, any note that is exactly the bank's memo. Anything else stays.
struct BankMemoNotesCleanup {
  static let doneKey = "bow.didClearBankMemoNotes"

  func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) throws {
    guard !defaults.bool(forKey: Self.doneKey) else { return }
    // Only items Bow created from the bank: imported ones, and pending ones entered early.
    // A transaction you entered and later matched kept your own notes.
    let records = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(
      predicate: #Predicate { $0.transactionID != nil && $0.memo != "" && $0.statusRaw != "linked" }
    ))
    var changed = false
    for record in records {
      guard let id = record.transactionID,
            let transaction = try BudgetTransactionLookup.byID(id, in: context) else { continue }
      if Self.isBankMemo(transaction.notes, memo: record.memo) {
        transaction.notes = ""
        changed = true
      }
    }
    if changed { try context.save() }
    defaults.set(true, forKey: Self.doneKey)
  }

  /// Saved notes are trimmed, so compare trimmed text.
  static func isBankMemo(_ notes: String, memo: String) -> Bool {
    let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedNotes.isEmpty && trimmedNotes == memo.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
