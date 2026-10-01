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
        // Items to review, due bills and pending items sit in their day; each row sets its own tint.
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
        }
        if feed.hasMore {
          ProgressView("Loading more…")
            .frame(maxWidth: .infinity)
            .onAppear { Task { await feed.loadNext() } }
        }
      }
    }
    .scrollsToTopOnReselect(of: .transactions)
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
    .navigationBarTitleDisplayMode(.inline)
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
