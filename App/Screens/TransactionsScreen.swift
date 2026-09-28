import SwiftUI
import SwiftData

struct TransactionsScreen: View {
  @Query private var simpleFINRecords: [SimpleFINImportRecord]
  var transactions: [BudgetTransaction]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  var onSelect: (UUID) -> Void
  @State private var searchText = ""
  @State private var filter = TransactionFilter()
  @State private var showingFilters = false

  private var visibleTransactions: [BudgetTransaction] {
    transactions
      .filter { transaction in
        filter.includes(TransactionFilterItem(
          accountID: transaction.accountID,
          transferAccountID: transaction.transferAccountID,
          envelopeID: transaction.envelopeID,
          date: transaction.date,
          amountMinor: transaction.amountMinor,
          isUncategorizedExpense: transaction.kind == .expense
            && transaction.envelopeID == nil,
          needsApproval: transaction.needsApproval
        )) && (searchText.isEmpty
          || transaction.payee.localizedCaseInsensitiveContains(searchText)
          || transaction.notes.localizedCaseInsensitiveContains(searchText)
          || accounts.first(where: { $0.id == transaction.accountID })?.name
            .localizedCaseInsensitiveContains(searchText) == true
          || envelopes.first(where: { $0.id == transaction.envelopeID })?.name
            .localizedCaseInsensitiveContains(searchText) == true)
      }
      .sorted {
        $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date
      }
  }

  var body: some View {
    List {
      let reviewCount = simpleFINRecords.filter { $0.status == .review }.count
      let approvalCount = transactions.filter(\.needsApproval).count
      let uncategorizedCount = transactions.filter { $0.kind == .expense && $0.envelopeID == nil }.count
      if reviewCount + approvalCount + uncategorizedCount > 0 {
        Section("Needs Attention") {
          if approvalCount > 0 {
            Button("Review \(approvalCount) imported transactions", systemImage: "checkmark.circle") {
              searchText = ""
              filter = TransactionFilter(needsApprovalOnly: true)
            }
          }
          if uncategorizedCount > 0 {
            Button("Categorize \(uncategorizedCount) transactions", systemImage: "tag") {
              searchText = ""
              filter = TransactionFilter(envelopeScope: .uncategorized)
            }
          }
          if reviewCount > 0 {
            NavigationLink {
              SimpleFINScreen()
            } label: {
              Label("Resolve \(reviewCount) bank transactions", systemImage: "arrow.clockwise")
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
      if visibleTransactions.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty && !filter.isActive ? "No transactions yet" : "No matches",
          systemImage: "list.bullet.rectangle",
          description: Text(searchText.isEmpty && !filter.isActive
            ? "Use the plus button to record your first transaction."
            : "Try a different search or clear your filters.")
        )
      } else {
        ForEach(visibleTransactions) { transaction in
          Button {
            onSelect(transaction.id)
          } label: {
            TransactionRow(
              transaction: transaction,
              accountName: accounts.first { $0.id == transaction.accountID }?.name ?? "Account",
              envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name,
              currencyCode: currencyCode
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .searchable(text: $searchText, prompt: "Payee, note, account, or envelope")
    .navigationTitle("Transactions")
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
