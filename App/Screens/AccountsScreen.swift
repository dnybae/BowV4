import SwiftUI

struct AccountsScreen: View {
  var accounts: [BudgetAccount]
  var transactions: [BudgetTransaction]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onAddAccount: () -> Void
  var onViewInsights: () -> Void
  var onSelectTransaction: (UUID) -> Void
  @State private var editingAccount: BudgetAccount?

  private var hasOnBudgetAccounts: Bool {
    accounts.contains { $0.kind == .cash || $0.kind == .credit }
  }

  private var hasOffBudgetAccounts: Bool {
    accounts.contains { $0.kind == .asset || $0.kind == .liability }
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("Net Worth")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(BudgetMoney.formatted(snapshot.netWorthMinor, currencyCode: currencyCode))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        }
        .padding(.vertical, 8)
        Button("View Insights", systemImage: "chart.bar.fill", action: onViewInsights)
      }

      if hasOnBudgetAccounts {
        Section("On Budget") {
          accountGroup(.cash, title: "Cash")
          accountGroup(.credit, title: "Credit Cards")
        }
      }

      if hasOffBudgetAccounts {
        Section("Off Budget") {
          accountGroup(.asset, title: "Assets")
          accountGroup(.liability, title: "Liabilities")
        }
      }

      Section {
        Button("Add Account", systemImage: "plus", action: onAddAccount)
      }
    }
    .navigationTitle("Accounts")
    .sheet(item: $editingAccount) { account in
      AccountEditorScreen(currencyCode: currencyCode, account: account)
    }
  }

  @ViewBuilder
  private func accountGroup(_ kind: BudgetAccountKind, title: String) -> some View {
    let matching = accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    if !matching.isEmpty {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
      ForEach(matching) { account in
        accountRow(account)
      }
    }
  }

  private func accountRow(_ account: BudgetAccount) -> some View {
    NavigationLink {
      AccountDetailScreen(
        account: account,
        transactions: transactions,
        balanceMinor: snapshot.accountBalances[account.id, default: 0],
        currencyCode: currencyCode,
        onSelectTransaction: onSelectTransaction,
        onEditAccount: { editingAccount = account }
      )
    } label: {
      HStack(spacing: 12) {
        Image(systemName: account.kind.systemImage)
          .foregroundStyle(.tint)
          .frame(width: 28)
          .accessibilityHidden(true)
        Text(account.name)
        Spacer()
        Text(BudgetMoney.formatted(
          snapshot.accountBalances[account.id, default: 0],
          currencyCode: currencyCode
        ))
        .fontWeight(.medium)
      }
    }
  }
}

private struct AccountDetailScreen: View {
  var account: BudgetAccount
  var transactions: [BudgetTransaction]
  var balanceMinor: Int64
  var currencyCode: String
  var onSelectTransaction: (UUID) -> Void
  var onEditAccount: () -> Void
  @State private var showingReconciliation = false

  private var accountTransactions: [BudgetTransaction] {
    transactions
      .filter { $0.accountID == account.id || $0.transferAccountID == account.id }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("Current Balance")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(BudgetMoney.formatted(balanceMinor, currencyCode: currencyCode))
            .font(.title.weight(.semibold))
        }
        .padding(.vertical, 8)
        Button("Reconcile Account", systemImage: "checkmark.circle") {
          showingReconciliation = true
        }
        if let date = account.lastReconciledAt,
           let balance = account.lastReconciledBalanceMinor {
          LabeledContent("Last Reconciled", value: date.formatted(date: .abbreviated, time: .omitted))
          LabeledContent("Statement Balance", value: BudgetMoney.formatted(balance, currencyCode: currencyCode))
        }
      }
      Section("Ledger") {
        if accountTransactions.isEmpty {
          ContentUnavailableView("No transactions yet", systemImage: "list.bullet.rectangle")
        } else {
          ForEach(accountTransactions) { transaction in
            Button {
              onSelectTransaction(transaction.id)
            } label: {
              TransactionRow(
                transaction: transaction,
                accountName: account.name,
                envelopeName: nil,
                currencyCode: currencyCode,
                displayAmountMinor: transaction.transferAccountID == account.id
                  ? -transaction.amountMinor : transaction.amountMinor
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle(account.name)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit Account", systemImage: "pencil", action: onEditAccount)
      }
    }
    .sheet(isPresented: $showingReconciliation) {
      ReconciliationScreen(account: account, transactions: accountTransactions, currencyCode: currencyCode)
    }
  }
}
