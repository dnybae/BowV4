import SwiftUI

struct AccountsScreen: View {
  var accounts: [BudgetAccount]
  var transactions: [BudgetTransaction]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onAddAccount: () -> Void
  var onViewInsights: () -> Void
  var onSelectTransaction: (UUID) -> Void
  @AppStorage("bow.collapsedAccountGroups") private var collapsedAccountGroups = ""
  @State private var editingAccount: BudgetAccount?

  private var hasOnBudgetAccounts: Bool {
    accounts.contains { $0.kind == .cash || $0.kind == .credit }
  }

  private var hasOffBudgetAccounts: Bool {
    accounts.contains { $0.kind == .asset || $0.kind == .liability }
  }

  private var collapsedKinds: Set<BudgetAccountKind> {
    Set(collapsedAccountGroups.split(separator: ",").compactMap {
      BudgetAccountKind(rawValue: String($0))
    })
  }

  var body: some View {
    ScrollView {
      if accounts.isEmpty {
        ContentUnavailableView {
          Label("No Accounts Yet", systemImage: "banknote.fill")
        } description: {
          Text("Add an account to start tracking your balances.")
        } actions: {
          Button("Add Account", systemImage: "plus", action: onAddAccount)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 30) {
          if hasOnBudgetAccounts {
            budgetGroup("On Budget") {
              accountGroup(.cash, title: "Cash")
              accountGroup(.credit, title: "Credit")
            }
          }

          if hasOffBudgetAccounts {
            budgetGroup("Off Budget") {
              accountGroup(.asset, title: "Assets")
              accountGroup(.liability, title: "Liabilities")
            }
          }

          netWorthCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 32)
      }
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Accounts")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Account", systemImage: "plus", action: onAddAccount)
      }
    }
    .sheet(item: $editingAccount) { account in
      NavigationStack {
        AccountEditorScreen(currencyCode: currencyCode, account: account)
      }
    }
  }

  @ViewBuilder
  private func budgetGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title)
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }

  @ViewBuilder
  private func accountGroup(_ kind: BudgetAccountKind, title: String) -> some View {
    let matching = accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    if !matching.isEmpty {
      let total = matching.reduce(0) { $0 + snapshot.accountBalances[$1.id, default: 0] }
      let formattedTotal = BudgetMoney.formatted(total, currencyCode: currencyCode)
      VStack(alignment: .leading, spacing: 12) {
        Button {
          withAnimation(.smooth) { toggleGroup(kind) }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: collapsedKinds.contains(kind) ? "chevron.right" : "chevron.down")
              .font(.caption.weight(.semibold))
              .frame(width: 16)
              .accessibilityHidden(true)
            Text(title)
              .font(.headline)
            Spacer(minLength: 8)
            Text(formattedTotal)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .foregroundStyle(.primary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), total \(formattedTotal)")
        .accessibilityValue(collapsedKinds.contains(kind) ? "Collapsed" : "Expanded")

        if !collapsedKinds.contains(kind) {
          VStack(spacing: 0) {
            ForEach(matching) { account in
              accountRow(account)
              if account.id != matching.last?.id {
                Divider()
                  .padding(.leading, 64)
              }
            }
          }
          .background(Color(uiColor: .secondarySystemGroupedBackground),
                      in: RoundedRectangle(cornerRadius: 24))
        }
      }
    }
  }

  private var netWorthCard: some View {
    Button(action: onViewInsights) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Net Worth")
            .font(.headline)
          Text("View Insights")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(BudgetMoney.formatted(snapshot.netWorthMinor, currencyCode: currencyCode))
          .font(.headline)
          .monospacedDigit()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .foregroundStyle(.primary)
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemGroupedBackground),
                  in: RoundedRectangle(cornerRadius: 24))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Net Worth, \(BudgetMoney.formatted(snapshot.netWorthMinor, currencyCode: currencyCode)). View Insights")
  }

  private func toggleGroup(_ kind: BudgetAccountKind) {
    var updated = collapsedKinds
    if !updated.insert(kind).inserted {
      updated.remove(kind)
    }
    collapsedAccountGroups = updated.map(\.rawValue).sorted().joined(separator: ",")
  }

  private func accountRow(_ account: BudgetAccount) -> some View {
    let balance = snapshot.accountBalances[account.id, default: 0]
    return NavigationLink {
      AccountDetailScreen(
        account: account,
        transactions: transactions,
        balanceMinor: balance,
        currencyCode: currencyCode,
        onSelectTransaction: onSelectTransaction,
        onEditAccount: { editingAccount = account }
      )
    } label: {
      HStack(spacing: 12) {
        Image(systemName: account.kind.systemImage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(uiColor: .systemBackground))
          .frame(width: 38, height: 38)
          .background(Color.accentColor, in: Circle())
          .accessibilityHidden(true)
        Text(account.name)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .multilineTextAlignment(.leading)
        Text(BudgetMoney.formatted(balance, currencyCode: currencyCode))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(account.kind == .cash && balance >= 0
            ? Color.accentColor : Color.primary)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(account.name), \(BudgetMoney.formatted(balance, currencyCode: currencyCode))")
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
        LabeledContent("Type", value: account.accountType.title)
        if !account.note.isEmpty {
          LabeledContent("Note", value: account.note)
        }
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
