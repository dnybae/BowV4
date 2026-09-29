import SwiftUI
import SwiftData

struct ReviewInboxScreen: View {
  @Environment(\.modelContext) private var modelContext
  var scheduledRecords: [BudgetTransaction]
  var records: [SimpleFINImportRecord]
  var occurrences: [BudgetScheduleOccurrence]
  var schedules: [BudgetSchedule]
  var accounts: [BudgetAccount]
  var currencyCode: String
  var onSelectTransaction: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var pendingSkip: BudgetScheduleOccurrence?
  @State private var message: String?
  @State private var feed = TransactionFeedModel()
  @State private var refreshVersion = 0

  private var otherItems: [ReviewEntry] {
    ReviewInbox(
      transactions: scheduledRecords, records: records,
      occurrences: occurrences, schedules: schedules
    ).items.filter {
      if case .transaction = $0 { return false }
      return true
    }
  }

  var body: some View {
    List {
      if feed.items.isEmpty && otherItems.isEmpty && !feed.isLoading {
        ContentUnavailableView(
          "All Caught Up", systemImage: "checkmark",
          description: Text("No transactions or scheduled bills need review.")
        )
      } else {
        ForEach(feed.items) { transaction in
          Button {
            onSelectTransaction(transaction.id)
          } label: {
            reviewRow(
              title: transaction.payee.isEmpty ? "Transaction" : transaction.payee,
              subtitle: "Review imported transaction · \(transaction.date.formatted(date: .abbreviated, time: .omitted))",
              amount: transaction.amountMinor,
              merchantName: transaction.kind == .transfer ? "" : transaction.payee,
              merchantDomain: transaction.kind == .transfer ? nil : transaction.merchantDomain
            )
          }
        }
        if feed.hasMore {
          ProgressView("Loading more…")
            .frame(maxWidth: .infinity)
            .onAppear { Task { await feed.loadNext() } }
        }
        ForEach(otherItems) { item in
          switch item {
          case .transaction(let transaction):
            Button {
              onSelectTransaction(transaction.id)
            } label: {
              reviewRow(
                title: transaction.payee.isEmpty ? "Transaction" : transaction.payee,
                subtitle: "Review imported transaction · \(transaction.date.formatted(date: .abbreviated, time: .omitted))",
                amount: transaction.amountMinor,
                merchantName: transaction.kind == .transfer ? "" : transaction.payee,
                merchantDomain: transaction.kind == .transfer ? nil : transaction.merchantDomain
              )
            }
          case .bankRecord(let record, let related):
            NavigationLink {
              SimpleFINReviewScreen(
                record: record, relatedOccurrence: related,
                relatedSchedule: related.flatMap { occurrence in
                  schedules.first { $0.id == occurrence.scheduleID }
                },
                onRecordScheduledTransfer: onRecord
              )
            } label: {
              reviewRow(
                title: record.payee.isEmpty ? "Bank transaction" : record.payee,
                subtitle: related == nil ? "Resolve bank match" : "Resolve bank match and scheduled bill",
                amount: record.amountMinor,
                merchantName: record.payee
              )
            }
          case .scheduled(let occurrence, let schedule):
            VStack(alignment: .leading, spacing: 10) {
              reviewRow(
                title: schedule.payee,
                subtitle: "Scheduled for \(occurrence.scheduledFor.formatted(date: .abbreviated, time: .omitted))",
                amount: -schedule.amountMinor,
                merchantName: schedule.kind == .transfer ? "" : schedule.payee
              )
              HStack {
                Button("Record Transaction", systemImage: "plus") {
                  onRecord(ScheduledTransactionDraft(
                    scheduleID: schedule.id,
                    scheduledFor: occurrence.scheduledFor,
                    accountID: schedule.accountID,
                    transferAccountID: schedule.transferAccountID,
                    envelopeID: schedule.envelopeID,
                    kind: schedule.kind,
                    amountMinor: schedule.amountMinor,
                    payee: schedule.payee,
                    notes: schedule.notes,
                    date: occurrence.scheduledFor
                  ))
                }
                .buttonStyle(.bordered)
                Button("Skip") { pendingSkip = occurrence }
                  .buttonStyle(.bordered)
              }
              Button("Edit Schedule", systemImage: "pencil") {
                onEditSchedule(schedule.id)
              }
              .font(.subheadline)
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
    .navigationTitle("Needs Approval")
    .task(id: refreshVersion) {
      await feed.reload(container: modelContext.container, searchText: "",
                        filter: TransactionFilter(needsApprovalOnly: true),
                        includeUncategorizedCount: false)
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("Skip this scheduled occurrence?", isPresented: Binding(
      get: { pendingSkip != nil }, set: { if !$0 { pendingSkip = nil } }
    )) {
      Button("Skip This Date", role: .destructive) {
        guard let pendingSkip else { return }
        pendingSkip.isSkipped = true
        do { try modelContext.save() }
        catch { message = error.localizedDescription }
        self.pendingSkip = nil
      }
    } message: {
      Text("The recurring schedule stays active for future dates.")
    }
    .alert("Couldn’t Update Review", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func reviewRow(
    title: String, subtitle: String, amount: Int64,
    merchantName: String, merchantDomain: String? = nil
  ) -> some View {
    HStack(spacing: 12) {
      MerchantLogoView(merchantName: merchantName, domain: merchantDomain)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).foregroundStyle(.primary)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(amount, currencyCode: currencyCode))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    }
    .contentShape(Rectangle())
  }
}
