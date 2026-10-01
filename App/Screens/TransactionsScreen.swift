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
  @Query private var bankConnections: [SimpleFINConnection]
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @State private var syncCoordinator = SimpleFINSyncCoordinator.shared
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var currencyCode: String
  var onSelect: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onEditSchedule: (UUID) -> Void
  var onReviewBankRecord: (SimpleFINImportRecord) -> Void
  var onAddTransaction: () -> Void
  var onConnectBank: () -> Void
  @State private var searchText = ""
  @State private var filter = TransactionFilter()
  @State private var showingFilters = false
  @State private var feed = TransactionFeedModel()
  @State private var scheduledRecords: [BudgetTransaction] = []
  @State private var refreshVersion = 0
  @State private var hasLoaded = false

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
      if syncCoordinator.isSyncing {
        BowLoadingLabel("Syncing with your bank…")
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .transition(.opacity)
      }
      if timeline.isEmpty && (!hasLoaded || feed.isLoading) {
        Section {
          BowTransactionSkeletonRows(count: 6)
        }
        .listRowBackground(Bow.card)
      } else if timeline.isEmpty {
        emptyState
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
                onRecord: onRecord, onEditSchedule: onEditSchedule,
                onReviewBankRecord: onReviewBankRecord
              )
            }
          }
        }
        if feed.hasMore {
          Section {
            BowTransactionSkeletonRows(count: 1)
              .onAppear { Task { await feed.loadNext() } }
          }
          .listRowBackground(Bow.card)
        }
      }
    }
    .bowAnimation(value: syncCoordinator.isSyncing)
    .bowAnimation(value: hasLoaded)
    .scrollsToTopOnReselect(of: .transactions)
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn, height: 320, showsTrail: false) }
    }
    .bowSoftScrollEdge()
    .bowMinimizesNavigationBarOnScroll()
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
      hasLoaded = true
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
      .bowHighVisibilityPriority()
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

extension TransactionsScreen {
  /// No transactions yet: what to do next. A search or filter with no results says so instead.
  @ViewBuilder
  fileprivate var emptyState: some View {
    if !searchText.isEmpty {
      ContentUnavailableView.search(text: searchText)
    } else if filter.isActive {
      ContentUnavailableView {
        Label("No matches", systemImage: "line.3.horizontal.decrease")
      } description: {
        Text("No transactions match these filters.")
      } actions: {
        Button("Clear Filters") { filter = TransactionFilter() }
          .bowSecondaryButton(size: .regular)
      }
    } else {
      let canConnect = bankConnections.isEmpty && !isDemoMode
      ContentUnavailableView {
        Label("No spending yet", systemImage: "list.bullet.rectangle")
      } description: {
        Text(canConnect
          ? "Add your first transaction, or connect your bank and Bow will bring them in for you."
          : "Add your first transaction to see it here.")
      } actions: {
        Button("Add Transaction", systemImage: "plus", action: onAddTransaction)
          .bowPrimaryButton(size: .regular)
        if canConnect {
          Button("Connect Bank", systemImage: "link", action: onConnectBank)
            .bowSecondaryButton(size: .regular)
        }
      }
    }
  }
}

private struct TransactionFeedKey: Hashable {
  var searchText: String
  var filter: TransactionFilter
  var refreshVersion: Int
}
