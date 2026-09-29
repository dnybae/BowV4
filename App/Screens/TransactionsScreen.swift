import SwiftUI
import SwiftData

struct TransactionsScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<SimpleFINImportRecord> { $0.statusRaw == "review" })
  private var simpleFINRecords: [SimpleFINImportRecord]
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

  private var reviewCount: Int {
    let other = ReviewInbox(
      transactions: scheduledRecords, records: simpleFINRecords,
      occurrences: occurrences, schedules: schedules
    ).items.filter {
      if case .transaction = $0 { return false }
      return true
    }.count
    return feed.approvalCount + other
  }

  var body: some View {
    List {
      if reviewCount > 0 {
        Section {
          NavigationLink(value: SpendingRoute.reviewInbox) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Transactions Needing Approval")
                .font(.headline)
              Text("\(reviewCount) \(reviewCount == 1 ? "item" : "items") to review, record, or resolve")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
          }
          .listRowBackground(Color.accentColor.opacity(0.10))
        }
      }
      if feed.uncategorizedCount > 0 {
        Section("Needs Attention") {
          Button("Categorize \(feed.uncategorizedCount) transactions", systemImage: "tag") {
            searchText = ""
            filter = TransactionFilter(envelopeScope: .uncategorized)
          }
        }
      }
      if filter.isActive {
        Section {
          HStack {
            Label("\(filter.activeCount) filters active", systemImage: "line.3.horizontal.decrease")
            Spacer()
            Button("Clear") { filter = TransactionFilter() }
          }
        }
      }
      if feed.items.isEmpty && feed.isLoading {
        ProgressView("Loading transactions…")
          .frame(maxWidth: .infinity)
      } else if feed.items.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty && !filter.isActive ? "No transactions yet" : "No matches",
          systemImage: "list.bullet.rectangle",
          description: Text(searchText.isEmpty && !filter.isActive
            ? "Use the plus button to record your first transaction."
            : "Try a different search or clear your filters.")
        )
      } else {
        if feed.didTrim {
          Button("Jump to Newest", systemImage: "arrow.up.to.line") {
            Task { await feed.returnToNewest(searchText: searchText, filter: filter) }
          }
        }
        ForEach(feed.items) { transaction in
          Button {
            onSelect(transaction.id)
          } label: {
            TransactionSummaryRow(
              transaction: transaction,
              currencyCode: currencyCode
            )
          }
          .buttonStyle(.plain)
        }
        if feed.hasMore {
          ProgressView("Loading more…")
            .frame(maxWidth: .infinity)
            .onAppear { Task { await feed.loadNext() } }
        }
      }
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
                        filter: filter, includeApprovalCount: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .navigationTitle("Spending")
    .navigationDestination(for: SpendingRoute.self) { route in
      switch route {
      case .reviewInbox:
        ReviewInboxScreen(
          scheduledRecords: scheduledRecords, records: simpleFINRecords,
          occurrences: occurrences, schedules: schedules,
          accounts: accounts, currencyCode: currencyCode,
          onSelectTransaction: onSelect, onRecord: onRecord,
          onEditSchedule: onEditSchedule
        )
      }
    }
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

  var body: some View {
    HStack(spacing: 12) {
      MerchantLogoView(
        merchantName: transaction.kind == .transfer ? "" : transaction.payee,
        domain: transaction.kind == .transfer ? nil : transaction.merchantDomain
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(transaction.kind == .transfer ? "Transfer" :
          transaction.payee.isEmpty ? "Transaction" : transaction.payee)
          .foregroundStyle(.primary)
        Text("\(transaction.accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
          .font(.caption).foregroundStyle(.secondary)
        if transaction.needsApproval {
          Text("Needs approval").font(.caption).foregroundStyle(.orange)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Needs categorization").font(.caption).foregroundStyle(.orange)
        } else if let envelopeName = transaction.envelopeName {
          Text(envelopeName).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(displayAmountMinor ?? transaction.amountMinor, currencyCode: currencyCode))
        .fontWeight(.medium)
        .foregroundStyle((displayAmountMinor ?? transaction.amountMinor) < 0 ? Color.primary : Color.accentColor)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

enum SpendingRoute: Hashable {
  case reviewInbox
}

struct TransactionRow: View {
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
        domain: transaction.kind == .transfer ? nil : transaction.merchantDomain
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .foregroundStyle(.primary)
        Text("\(accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
          .font(.caption)
          .foregroundStyle(.secondary)
        if transaction.needsApproval {
          Text("Needs approval")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Needs categorization")
            .font(.caption)
            .foregroundStyle(.orange)
        } else if let envelopeName {
          Text(envelopeName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(
        displayAmountMinor ?? transaction.amountMinor,
        currencyCode: currencyCode
      ))
        .fontWeight(.medium)
        .foregroundStyle((displayAmountMinor ?? transaction.amountMinor) < 0
          ? Color.primary : Color.accentColor)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
