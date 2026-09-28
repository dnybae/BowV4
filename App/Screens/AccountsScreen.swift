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

  private var onBudgetAccounts: [BudgetAccount] {
    accounts(for: [.cash, .credit])
  }

  private var offBudgetAccounts: [BudgetAccount] {
    accounts(for: [.asset, .liability])
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

      if !onBudgetAccounts.isEmpty {
        Section("On Budget") {
          ForEach(onBudgetAccounts) { account in
            accountRow(account)
          }
        }
      }

      if !offBudgetAccounts.isEmpty {
        Section("Off Budget") {
          ForEach(offBudgetAccounts) { account in
            accountRow(account)
          }
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

  private func accounts(for kinds: [BudgetAccountKind]) -> [BudgetAccount] {
    kinds.flatMap { kind in
      accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
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
        VStack(alignment: .leading, spacing: 2) {
          Text(account.name)
          Text(account.kind.title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
