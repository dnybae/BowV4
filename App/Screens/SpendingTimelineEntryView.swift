import SwiftUI
import SwiftData

struct SpendingTimelineEntryView: View {
  @Environment(\.modelContext) private var modelContext
  var item: SpendingTimelineItem
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var schedules: [BudgetSchedule]
  var onSelect: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var message: String?

  private var model: TransactionRowModel { TransactionRowModel(item) }

  var body: some View {
    Group {
      switch item.source {
      case .transaction(let id):
        Button { onSelect(id) } label: { row }
          .buttonStyle(.plain)
      case .bankReview(let record, let related)
        where record.status == .imported && related == nil && record.transactionID != nil:
        // Already imported as a transaction: approve it in the review sheet.
        Button { record.transactionID.map(onSelect) } label: { row }
          .buttonStyle(.plain)
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
          .buttonStyle(.plain)
          .accessibilityHint("Opens the bill to record it")
          .swipeActions(edge: .leading) {
            Button("Record", systemImage: "plus") { record(occurrence, schedule) }
              .tint(.accentColor)
          }
          .swipeActions(edge: .trailing) {
            Button("Skip", systemImage: "forward") { skip(occurrence) }
          }
          .contextMenu {
            Button("Record", systemImage: "plus") { record(occurrence, schedule) }
            Button("Skip This Date", systemImage: "forward") { skip(occurrence) }
            Button("Edit Schedule", systemImage: "calendar") { onEditSchedule(schedule.id) }
          }
      }
    }
    .listRowBackground(model.state.rowStatus?.rowBackground ?? Bow.card)
    .alert("Couldn’t Update Bill", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
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

  private func skip(_ occurrence: BudgetScheduleOccurrence) {
    occurrence.isSkipped = true
    do { try modelContext.save() }
    catch { message = error.localizedDescription }
  }
}
