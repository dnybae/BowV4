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

  private var inbox: ReviewInbox {
    let approvalIDs = Set(approvals.map(\.id))
    let reviewTransactions = approvals + legacyUncategorized.filter { !approvalIDs.contains($0.id) }
    let known = Set(reviewTransactions.map(\.id))
    return ReviewInbox(
      transactions: reviewTransactions + scheduledRecords.filter { !known.contains($0.id) },
      records: simpleFINRecords,
      occurrences: occurrences, schedules: schedules
    )
  }

  private var pendingCount: Int {
    simpleFINRecords.filter { $0.bankState == .pending && $0.isVisiblePending }.count
  }

  var body: some View {
    List {
      if !inbox.bankItems.isEmpty || pendingCount > 0 || !inbox.scheduledItems.isEmpty {
        Section {
          if !inbox.bankItems.isEmpty {
            NavigationLink(value: SpendingRoute.reviewInbox) {
              Label {
                VStack(alignment: .leading, spacing: 3) {
                  Text("Review bank transactions").font(.headline)
                  Text("\(inbox.bankItems.count) \(inbox.bankItems.count == 1 ? "item needs" : "items need") a decision")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
              } icon: {
                Image(systemName: "checkmark.circle")
                  .foregroundStyle(.tint)
              }
              .padding(.vertical, 5)
            }
          }
          if pendingCount > 0 {
            NavigationLink(value: SpendingRoute.pendingBank) {
              Label {
                VStack(alignment: .leading, spacing: 3) {
                  Text("Pending at bank").font(.headline)
                  Text("\(pendingCount) \(pendingCount == 1 ? "authorization" : "authorizations") · not in your budget")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
              } icon: {
                Image(systemName: "clock").foregroundStyle(.orange)
              }
              .padding(.vertical, 5)
            }
          }
          if !inbox.scheduledItems.isEmpty {
            NavigationLink(value: SpendingRoute.scheduledBills) {
              Label {
                VStack(alignment: .leading, spacing: 3) {
                  Text("Scheduled bills").font(.headline)
                  Text("\(inbox.scheduledItems.count) due to record or skip")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
              } icon: {
                Image(systemName: "calendar").foregroundStyle(.secondary)
              }
              .padding(.vertical, 5)
            }
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
        ForEach(TransactionDateGroup.make(feed.items)) { group in
          Section(group.title) {
            ForEach(group.items) { transaction in
              Button {
                onSelect(transaction.id)
              } label: {
                TransactionSummaryRow(
                  transaction: transaction,
                  currencyCode: currencyCode,
                  showsDate: false
                )
              }
              .buttonStyle(.plain)
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
    .navigationDestination(for: SpendingRoute.self) { route in
      switch route {
      case .reviewInbox:
        ReviewInboxScreen(
          mode: .bank,
          scheduledRecords: scheduledRecords, records: simpleFINRecords,
          occurrences: occurrences, schedules: schedules,
          accounts: accounts, currencyCode: currencyCode,
          onSelectTransaction: onSelect, onRecord: onRecord,
          onEditSchedule: onEditSchedule
        )
      case .scheduledBills:
        ReviewInboxScreen(
          mode: .scheduled,
          scheduledRecords: scheduledRecords, records: simpleFINRecords,
          occurrences: occurrences, schedules: schedules,
          accounts: accounts, currencyCode: currencyCode,
          onSelectTransaction: onSelect, onRecord: onRecord,
          onEditSchedule: onEditSchedule
        )
      case .pendingBank:
        PendingBankScreen(
          records: simpleFINRecords, accounts: accounts,
          envelopes: envelopes, onSelectTransaction: onSelect
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
          .foregroundStyle(.primary)
        Text(showsDate
          ? "\(transaction.accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))"
          : transaction.accountName)
          .font(.caption).foregroundStyle(.secondary)
        if transaction.needsApproval {
          Text("Needs review").font(.caption).foregroundStyle(.orange)
        } else if transaction.sourceRaw == "manualLinked" {
          Label("Matched", systemImage: "link")
            .font(.caption).foregroundStyle(.tint)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Choose an envelope in Bank Review").font(.caption).foregroundStyle(.orange)
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
  case scheduledBills
  case pendingBank
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
          .foregroundStyle(.primary)
        Text("\(accountName) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
          .font(.caption)
          .foregroundStyle(.secondary)
        if transaction.needsApproval {
          Text("Needs review")
            .font(.caption)
            .foregroundStyle(.orange)
        } else if transaction.sourceRaw == "manualLinked" {
          Label("Matched", systemImage: "link")
            .font(.caption).foregroundStyle(.tint)
        }
        if transaction.envelopeID == nil && transaction.kind == .expense {
          Text("Choose an envelope in Bank Review")
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
