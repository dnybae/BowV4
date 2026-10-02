import Foundation

/// What a transaction sheet opens on. Every row in every state opens the same sheet.
enum TransactionSheetSubject {
  case new(preferredAccountID: UUID? = nil)
  case existing(BudgetTransaction)
  /// Posted at the bank and not in the budget yet.
  case bankItem(SimpleFINImportRecord)
  /// Pending at the bank and not entered yet.
  case pendingItem(SimpleFINImportRecord)
  /// A scheduled bill or deposit that's come due.
  case scheduled(ScheduledTransactionDraft)
}
