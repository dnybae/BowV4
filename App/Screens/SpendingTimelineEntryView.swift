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
  /// Shows Skip and Record buttons under scheduled bills, for the Needs attention section.
  var showsInlineActions = false
  @State private var showingScheduledActions = false
  @State private var message: String?

  var body: some View {
    Group {
      switch item.source {
      case .transaction(let id):
        Button { onSelect(id) } label: { row }
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
        VStack(alignment: .trailing, spacing: Bow.Space.s2) {
          Button { showingScheduledActions = true } label: { row }
            .buttonStyle(.plain)
          if showsInlineActions {
            HStack(spacing: Bow.Space.s2) {
              Button("Skip") { skip(occurrence) }
                .bowSecondaryButton(size: .small)
              Button("Record") { record(occurrence, schedule) }
                .bowPrimaryButton(size: .small)
            }
            .padding(.bottom, Bow.Space.s1)
          }
        }
          .swipeActions(edge: .leading) {
            Button("Record", systemImage: "plus") { record(occurrence, schedule) }
              .tint(.accentColor)
          }
          .swipeActions(edge: .trailing) {
            Button("Skip", systemImage: "forward") { skip(occurrence) }
          }
          .confirmationDialog(
            schedule.payee.isEmpty ? "Scheduled bill" : schedule.payee,
            isPresented: $showingScheduledActions, titleVisibility: .visible
          ) {
            Button("Record") { record(occurrence, schedule) }
            Button("Skip This Date", role: .destructive) { skip(occurrence) }
            Button("Edit Schedule") { onEditSchedule(schedule.id) }
          } message: {
            Text("Due \(occurrence.scheduledFor.formatted(date: .abbreviated, time: .omitted)). Skipping keeps the schedule active for future dates.")
          }
      }
    }
    .alert("Couldn’t Update Bill", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private var row: some View {
    SpendingTimelineRow(item: item)
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

private struct SpendingTimelineRow: View {
  @Query private var payees: [BudgetPayee]
  var item: SpendingTimelineItem

  private var isPending: Bool {
    item.status == .pending || item.status == .pendingEntered
  }

  var body: some View {
    HStack(spacing: 12) {
      MerchantLogoView(
        merchantName: item.kind == .transfer ? "" : item.title,
        domain: item.kind == .transfer ? nil : PayeeDirectory.logoDomain(
          for: item.title, transactionDomain: item.merchantDomain, payees: payees
        ),
        kind: item.kind,
        categoryName: item.envelopeName
      )
      .opacity(isPending ? 0.6 : 1)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .foregroundStyle(isPending ? Bow.inkSoft : Bow.ink)
        Text(item.envelopeName.map { "\(item.accountName) · \($0)" } ?? item.accountName)
          .font(.caption)
          .foregroundStyle(Bow.inkSoft)
        if let status = item.status {
          Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(status.needsAttention ? .medium : .regular))
            .foregroundStyle(status.needsAttention ? AnyShapeStyle(Bow.needsInk) : AnyShapeStyle(Bow.inkSoft))
        } else if item.isMatched {
          Label("Matched", systemImage: "link")
            .font(.caption)
            .foregroundStyle(.tint)
        }
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(item.amountMinor, currencyCode: item.currencyCode))
        .fontWeight(.medium)
        .foregroundStyle(isPending
          ? AnyShapeStyle(Bow.inkSoft)
          : item.amountMinor < 0 ? AnyShapeStyle(Bow.ink) : AnyShapeStyle(.tint))
        .fontDesign(.rounded).monospacedDigit()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
