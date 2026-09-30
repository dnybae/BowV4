import SwiftUI
import SwiftData

struct TransactionsScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query
  private var simpleFINRecords: [SimpleFINImportRecord]
  @Query(filter: #Predicate<BudgetTransaction> { $0.needsApproval })
  private var approvals: [BudgetTransaction]
  @Query(filter: #Predicate<BudgetTransaction> {
    $0.kindRaw == "expense" && $0.envelopeID == nil
  })
  private var legacyUncategorized: [BudgetTransaction]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var currencyCode: String
  var onSelect: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var searchText = ""
  @State private var filter = TransactionFilter()
  @State private var showingFilters = false
  @State private var feed = TransactionFeedModel()
  @State private var scheduledRecords: [BudgetTransaction] = []
  @State private var refreshVersion = 0

  private var reviewTransactions: [BudgetTransaction] {
    let approvalIDs = Set(approvals.map(\.id))
    let unresolved = approvals + legacyUncategorized.filter { !approvalIDs.contains($0.id) }
    let known = Set(unresolved.map(\.id))
    return unresolved + scheduledRecords.filter { !known.contains($0.id) }
  }

  private var inbox: ReviewInbox {
    return ReviewInbox(
      transactions: reviewTransactions,
      records: simpleFINRecords,
      occurrences: occurrences, schedules: schedules
    )
  }

  private var timeline: SpendingTimeline {
    SpendingTimeline(
      transactions: feed.items, reviewTransactions: reviewTransactions,
      inbox: inbox, records: simpleFINRecords,
      accounts: accounts, envelopes: envelopes,
      currencyCode: currencyCode, searchText: searchText, filter: filter
    )
  }

  private var attentionSummary: String {
    switch timeline.needsAttention.count {
    case 0: "All caught up"
    case 1: "1 thing needs you"
    case let count: "\(count) things need you"
    }
  }

  var body: some View {
    List {
      if filter.isActive {
        Section {
          HStack {
            Label("\(filter.activeCount) filters active", systemImage: "line.3.horizontal.decrease")
            Spacer()
            Button("Clear") { filter = TransactionFilter() }
          }
        }
        .listRowBackground(Bow.card)
      }
      if timeline.isEmpty && feed.isLoading {
        ProgressView("Loading transactions…")
          .frame(maxWidth: .infinity)
      } else if timeline.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty && !filter.isActive ? "No spending activity yet" : "No matches",
          systemImage: "list.bullet.rectangle",
          description: Text(searchText.isEmpty && !filter.isActive
            ? "Transactions, bank activity, and due bills will appear here."
            : "Try a different search or clear your filters.")
        )
      } else {
        if feed.didTrim {
          Button("Jump to Newest", systemImage: "arrow.up.to.line") {
            Task { await feed.returnToNewest(searchText: searchText, filter: filter) }
          }
          .listRowBackground(Bow.card)
        }
        if !timeline.needsAttention.isEmpty {
          Section {
            ForEach(timeline.needsAttention) { item in
              SpendingTimelineEntryView(
                item: item, accounts: accounts, envelopes: envelopes,
                schedules: schedules, onSelect: onSelect,
                onRecord: onRecord, onEditSchedule: onEditSchedule,
                showsInlineActions: true
              )
            }
          } header: {
            HStack {
              Text("Needs attention")
              Spacer()
              Text(timeline.needsAttention.count, format: .number)
                .monospacedDigit()
            }
          }
          .listRowBackground(Bow.card)
        }
        ForEach(timeline.days) { group in
          Section(group.title) {
            ForEach(group.items) { item in
              SpendingTimelineEntryView(
                item: item, accounts: accounts, envelopes: envelopes,
                schedules: schedules, onSelect: onSelect,
                onRecord: onRecord, onEditSchedule: onEditSchedule
              )
            }
          }
          .listRowBackground(Bow.card)
        }
        if feed.hasMore {
          ProgressView("Loading more…")
            .frame(maxWidth: .infinity)
            .onAppear { Task { await feed.loadNext() } }
        }
      }
    }
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn, height: 320, showsTrail: false) }
    }
    .searchable(text: $searchText, prompt: "Payee, note, account, or envelope")
    .task(id: TransactionFeedKey(searchText: searchText, filter: filter,
                                 refreshVersion: refreshVersion)) {
      if !searchText.isEmpty {
        try? await Task.sleep(for: .milliseconds(250))
      }
      guard !Task.isCancelled else { return }
      scheduledRecords = (try? ScheduledRecordLookup().transactions(
        for: occurrences, in: modelContext
      )) ?? []
      await feed.reload(container: modelContext.container, searchText: searchText,
                        filter: filter, includeUncategorizedCount: false)
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .navigationTitle("Spending")
    .navigationSubtitle(attentionSummary)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Filter Transactions", systemImage: "line.3.horizontal.decrease") {
          showingFilters = true
        }
        .accessibilityLabel(filter.isActive
          ? "Filter Transactions, \(filter.activeCount) active"
          : "Filter Transactions")
      }
    }
    .sheet(isPresented: $showingFilters) {
      TransactionFilterScreen(
        filters: $filter,
        accounts: accounts,
        envelopes: envelopes,
        currencyCode: currencyCode
      )
    }
  }
}

private struct TransactionFeedKey: Hashable {
  var searchText: String
  var filter: TransactionFilter
  var refreshVersion: Int
}

struct TransactionSummaryRow: View {
  var transaction: TransactionListItem
  var currencyCode: String
  var displayAmountMinor: Int64? = nil
  var showsDate = true

  var body: some View {
    HStack(spacing: 12) {
      MerchantLogoView(
        merchantName: transaction.kind == .transfer ? "" : transaction.payee,
        domain: transaction.kind == .transfer ? nil : transaction.merchantDomain,
        kind: transaction.kind,
        categoryName: transaction.envelopeName
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(transaction.kind == .transfer ? "Transfer" :
          transaction.payee.isEmpty ? "Transaction" : transaction.payee)
          .foregroundStyle(Bow.ink)
        Text(showsDate
          ? "\(transaction.accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))"
          : transaction.accountName)
          .font(.caption).foregroundStyle(Bow.inkSoft)
        if transaction.needsApproval {
          Text("Needs review").font(.caption).foregroundStyle(Bow.needsInk)
        } else if transaction.sourceRaw == "manualLinked" {
          Label("Matched", systemImage: "link")
            .font(.caption).foregroundStyle(.tint)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Choose an envelope in Bank Review").font(.caption).foregroundStyle(Bow.needsInk)
        } else if let envelopeName = transaction.envelopeName {
          Text(envelopeName).font(.caption).foregroundStyle(Bow.inkSoft)
        }
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(displayAmountMinor ?? transaction.amountMinor, currencyCode: currencyCode))
        .fontWeight(.medium)
        .foregroundStyle((displayAmountMinor ?? transaction.amountMinor) < 0 ? Bow.ink : Color.accentColor)
        .fontDesign(.rounded).monospacedDigit()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

struct TransactionRow: View {
  @Query private var payees: [BudgetPayee]
  var transaction: BudgetTransaction
  var accountName: String
  var envelopeName: String?
  var currencyCode: String
  var displayAmountMinor: Int64? = nil

  private var title: String {
    if transaction.kind == .transfer { return "Transfer" }
    return transaction.payee.isEmpty ? "Transaction" : transaction.payee
  }

  var body: some View {
    HStack(spacing: 12) {
      MerchantLogoView(
        merchantName: transaction.kind == .transfer ? "" : transaction.payee,
        domain: transaction.kind == .transfer ? nil : PayeeDirectory.logoDomain(
          for: transaction.payee, transactionDomain: transaction.merchantDomain, payees: payees
        ),
        kind: transaction.kind,
        categoryName: envelopeName
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .foregroundStyle(Bow.ink)
        Text("\(accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
          .font(.caption)
          .foregroundStyle(Bow.inkSoft)
        if transaction.needsApproval {
          Text("Needs review")
            .font(.caption)
            .foregroundStyle(Bow.needsInk)
        } else if transaction.sourceRaw == "manualLinked" {
          Label("Matched", systemImage: "link")
            .font(.caption).foregroundStyle(.tint)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Choose an envelope in Bank Review")
            .font(.caption)
            .foregroundStyle(Bow.needsInk)
        } else if let envelopeName {
          Text(envelopeName)
            .font(.caption)
            .foregroundStyle(Bow.inkSoft)
        }
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(
        displayAmountMinor ?? transaction.amountMinor,
        currencyCode: currencyCode
      ))
        .fontWeight(.medium)
        .foregroundStyle((displayAmountMinor ?? transaction.amountMinor) < 0
          ? Bow.ink : Color.accentColor)
        .fontDesign(.rounded).monospacedDigit()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
