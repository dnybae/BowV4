import SwiftUI
import SwiftData

enum ReviewInboxMode {
  case bank
  case scheduled
}

struct ReviewInboxScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<BudgetTransaction> { $0.needsApproval })
  private var approvals: [BudgetTransaction]
  @Query(filter: #Predicate<BudgetTransaction> {
    $0.kindRaw == "expense" && $0.envelopeID == nil
  })
  private var legacyUncategorized: [BudgetTransaction]
  @Query private var payees: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
  var mode: ReviewInboxMode = .bank
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

  private var inbox: ReviewInbox {
    let approvalIDs = Set(approvals.map(\.id))
    let reviewTransactions = approvals + legacyUncategorized.filter { !approvalIDs.contains($0.id) }
    let known = Set(reviewTransactions.map(\.id))
    return ReviewInbox(
      transactions: reviewTransactions + scheduledRecords.filter { !known.contains($0.id) },
      records: records, occurrences: occurrences, schedules: schedules
    )
  }

  var body: some View {
    List {
      let entries = mode == .bank ? inbox.bankItems : inbox.scheduledItems
      if entries.isEmpty {
        ContentUnavailableView(
          mode == .bank ? "All Caught Up" : "No Bills Due",
          systemImage: "checkmark",
          description: Text(mode == .bank
            ? "No bank transactions need a decision."
            : "Scheduled bills will appear here when they are due.")
        )
      } else {
        Section {
          ForEach(entries) { item in
            switch item {
            case .transaction(let transaction):
              Button {
                onSelectTransaction(transaction.id)
              } label: {
                reviewRow(
                  title: transaction.payee.isEmpty ? "Transaction" : transaction.payee,
                  subtitle: transaction.envelopeID == nil
                    ? "Choose an envelope · \(transaction.date.formatted(date: .abbreviated, time: .omitted))"
                    : "Review existing import · \(transaction.date.formatted(date: .abbreviated, time: .omitted))",
                  amount: transaction.amountMinor,
                  merchantName: transaction.kind == .transfer ? "" : transaction.payee,
                  merchantDomain: transaction.merchantDomain,
                  kind: transaction.kind,
                  categoryName: envelopes.first { $0.id == transaction.envelopeID }?.name
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
                  subtitle: accounts.first { $0.id == record.localAccountID }?.name ?? "Bank account",
                  amount: record.amountMinor,
                  merchantName: record.payee,
                  kind: record.amountMinor >= 0 ? .inflow : .expense
                )
              }
            case .scheduled(let occurrence, let schedule):
              VStack(alignment: .leading, spacing: 12) {
                reviewRow(
                  title: schedule.payee,
                  subtitle: "Due \(occurrence.scheduledFor.formatted(date: .abbreviated, time: .omitted))",
                  amount: -schedule.amountMinor,
                  merchantName: schedule.kind == .transfer ? "" : schedule.payee,
                  kind: schedule.kind,
                  categoryName: envelopes.first { $0.id == schedule.envelopeID }?.name
                )
                HStack {
                  Button("Record", systemImage: "plus") {
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
                  .buttonStyle(.borderedProminent)
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
        } footer: {
          if mode == .bank {
            Text("Choose a match or an envelope once. Matching keeps your existing entry; adding creates a new one.")
          }
        }
      }
    }
    .navigationTitle(mode == .bank ? "Bank Review" : "Scheduled Bills")
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
    merchantName: String, merchantDomain: String? = nil,
    kind: BudgetTransactionKind? = nil, categoryName: String? = nil
  ) -> some View {
    HStack(spacing: 12) {
      MerchantLogoView(
        merchantName: merchantName,
        domain: merchantName.isEmpty ? nil : PayeeDirectory.logoDomain(
          for: merchantName, transactionDomain: merchantDomain, payees: payees
        ),
        kind: kind,
        categoryName: categoryName
      )
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
