import SwiftUI
import SwiftData

struct TransactionsScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  @Query
  private var simpleFINRecords: [SimpleFINImportRecord]
  @Query(filter: #Predicate<BudgetTransaction> { $0.needsApproval })
  private var approvals: [BudgetTransaction]
  @Query(filter: #Predicate<BudgetTransaction> {
    $0.kindRaw == "expense" && $0.envelopeID == nil
      && $0.sourceRaw != "balanceAdjustment" && !$0.isBeforeStart
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
  var onReviewBankRecord: (SimpleFINImportRecord, BudgetScheduleOccurrence?) -> Void
  var onEnterPending: (SimpleFINImportRecord) -> Void
  var onAddTransaction: () -> Void
  var onConnectBank: () -> Void
  @State private var searchText = ""
  @State private var filter = TransactionFilter()
  @State private var showingFilters = false
  @State private var feed = TransactionFeedModel()
  @State private var scheduledRecords: [BudgetTransaction] = []
  @State private var refreshVersion = 0
  @State private var hasLoaded = false
  @State private var swipeError: String?

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
                item: item, onSelect: onSelect, onRecord: onRecord,
                onReviewBankRecord: onReviewBankRecord, onEnterPending: onEnterPending
              )
              .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(for: item) }
              .swipeActions(edge: .leading) { leadingSwipe(for: item) }
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
    .refreshable { await refreshFromBank() }
    .bowErrorAlert("Spending", message: $swipeError)
    .navigationTitle("Spending")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showingFilters = true
        } label: { BowToolbarLabel("Filter Transactions", systemImage: "line.3.horizontal.decrease") }
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

// MARK: - Swipe actions and refresh

extension TransactionsScreen {
  /// Delete a transaction, skip a bill's date, or ignore a bank item, straight from its row.
  @ViewBuilder
  fileprivate func trailingSwipe(for item: SpendingTimelineItem) -> some View {
    switch item.source {
    case .transaction(let id):
      Button("Delete", systemImage: "trash", role: .destructive) { deleteTransaction(id) }
    case .scheduled(let occurrence, let schedule):
      Button("Skip", systemImage: "forward.end") { skip(occurrence, of: schedule) }
        .tint(Bow.needs)
    case .bankReview(let record, _):
      Button("Ignore", systemImage: "eye.slash", role: .destructive) { ignore(record) }
    case .pending:
      EmptyView()
    }
  }

  /// Marks a transaction cleared or uncleared, as the bank would.
  @ViewBuilder
  fileprivate func leadingSwipe(for item: SpendingTimelineItem) -> some View {
    if case .transaction(let id) = item.source,
       let transaction = try? BudgetTransactionLookup.byID(id, in: modelContext),
       transaction.reconciledAt == nil, !transaction.isBalanceAdjustment {
      Button(transaction.isCleared ? "Uncleared" : "Cleared",
             systemImage: transaction.isCleared ? "circle" : "checkmark.circle") {
        transaction.isCleared.toggle()
        try? modelContext.save()
      }
      .tint(Bow.funded)
    }
  }

  private func deleteTransaction(_ id: UUID) {
    do {
      guard let transaction = try BudgetTransactionLookup.byID(id, in: modelContext) else { return }
      let title = transaction.payee.isEmpty ? "Transaction" : transaction.payee
      let undo = try UndoableChanges.delete(transaction, in: modelContext)
      toasts?.show(.deleted("Deleted · \(title)", undo: undo))
    } catch {
      swipeError = error.localizedDescription
    }
  }

  private func skip(_ occurrence: BudgetScheduleOccurrence, of schedule: BudgetSchedule) {
    do {
      try BudgetCommands.skipScheduledDate(scheduleID: schedule.id, on: occurrence.scheduledFor, in: modelContext)
      try modelContext.save()
      toasts?.show(.deleted("Skipped · \(schedule.payee.isEmpty ? "Scheduled bill" : schedule.payee)"))
    } catch {
      swipeError = error.localizedDescription
    }
  }

  private func ignore(_ record: SimpleFINImportRecord) {
    do {
      try SimpleFINSyncCoordinator.shared.resolve(record, as: .ignore, in: modelContext)
      toasts?.show(.deleted("Ignored · \(record.payee.isEmpty ? "Bank transaction" : record.payee)"))
    } catch {
      swipeError = error.localizedDescription
    }
  }

  /// Pull to refresh asks the bank for anything new, when a bank is connected.
  fileprivate func refreshFromBank() async {
    guard !isDemoMode, !bankConnections.isEmpty else {
      refreshVersion += 1
      return
    }
    do {
      let summary = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
      let arrived = summary.imported + summary.needsReview
      toasts?.show(BowToast(
        message: arrived == 0 ? "You’re up to date"
          : arrived == 1 ? "1 new transaction from your bank" : "\(arrived) new transactions from your bank",
        systemImage: "building.columns.fill", feedback: .quiet
      ))
    } catch {
      toasts?.show(BowToast(message: error.localizedDescription,
                            systemImage: "exclamationmark.circle.fill", feedback: .quiet))
    }
  }
}

private struct TransactionFeedKey: Hashable {
  var searchText: String
  var filter: TransactionFilter
  var refreshVersion: Int
}
