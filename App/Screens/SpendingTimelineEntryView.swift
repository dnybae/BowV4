import SwiftUI

struct SpendingTimelineEntryView: View {
  var item: SpendingTimelineItem
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var schedules: [BudgetSchedule]
  var onSelect: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onReviewBankRecord: (SimpleFINImportRecord) -> Void

  private var model: TransactionRowModel { TransactionRowModel(item) }

  var body: some View {
    Group {
      switch item.source {
      case .transaction(let id):
        Button { onSelect(id) } label: { row }
      case .bankReview(let record, let related)
        where record.status == .imported && related == nil && record.transactionID != nil:
        // Already imported as a transaction: approve it in the review sheet.
        Button { record.transactionID.map(onSelect) } label: { row }
      case .bankReview(let record, let related) where record.status == .review && related == nil:
        // Not in the budget yet: match it or add it in the review sheet.
        Button { onReviewBankRecord(record) } label: { row }
      case .bankReview(let record, let related):
        NavigationLink {
          SimpleFINReviewScreen(
            record: record, relatedOccurrence: related,
            relatedSchedule: related.flatMap { occurrence in
              schedules.first { $0.id == occurrence.scheduleID }
            },
            onRecordScheduledTransfer: onRecord
          )
        } label: { row }
      case .pending(let record):
        NavigationLink {
          PendingBankDetailScreen(
            record: record, accounts: accounts, envelopes: envelopes,
            onSelectTransaction: onSelect
          )
        } label: { row }
      case .scheduled(let occurrence, let schedule):
        // Tapping opens the bill in the editor to record it.
        Button { record(occurrence, schedule) } label: { row }
          .accessibilityHint("Opens the bill to record it")
      }
    }
    .listRowBackground(model.state.rowStatus?.rowBackground ?? Bow.card)
  }

  private var row: some View {
    TransactionRowView(model: model, currencyCode: item.currencyCode)
  }

  private func record(_ occurrence: BudgetScheduleOccurrence, _ schedule: BudgetSchedule) {
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
