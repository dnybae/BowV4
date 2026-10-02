import SwiftUI

/// A Spending row. Every row, in every state, opens the same transaction sheet.
struct SpendingTimelineEntryView: View {
  var item: SpendingTimelineItem
  var onSelect: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onReviewBankRecord: (SimpleFINImportRecord, BudgetScheduleOccurrence?) -> Void
  var onEnterPending: (SimpleFINImportRecord) -> Void

  private var model: TransactionRowModel { TransactionRowModel(item) }

  var body: some View {
    Button(action: open) {
      TransactionRowView(model: model, currencyCode: item.currencyCode)
    }
    .listRowBackground(model.state.rowStatus?.rowBackground ?? Bow.card)
  }

  private func open() {
    switch item.source {
    case .transaction(let id):
      onSelect(id)
    case .bankReview(let record, let related):
      onReviewBankRecord(record, related)
    case .pending(let record):
      // Already entered: it's your transaction. Otherwise enter it now.
      if let id = record.transactionID {
        onSelect(id)
      } else {
        onEnterPending(record)
      }
    case .scheduled(let occurrence, let schedule):
      onRecord(ScheduledTransactionDraft(
        scheduleID: schedule.id,
        scheduledFor: occurrence.scheduledFor,
        accountID: schedule.accountID,
        transferAccountID: schedule.transferAccountID,
        envelopeID: schedule.envelopeID, kind: schedule.kind,
        amountMinor: schedule.amountMinor, payee: schedule.payee,
        notes: schedule.notes, date: occurrence.scheduledFor
      ))
    }
  }
}
