import SwiftUI

struct AccountsScreen: View {
  var accounts: [BudgetAccount]
  var transactions: [BudgetTransaction]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onAddAccount: () -> Void
  var onSelectTransaction: (UUID) -> Void

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
      }

      ForEach(BudgetAccountKind.allCases) { kind in
        let matching = accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
        if !matching.isEmpty {
          Section(kind.title) {
            ForEach(matching) { account in
              NavigationLink {
                AccountDetailScreen(
                  account: account,
                  transactions: transactions,
                  balanceMinor: snapshot.accountBalances[account.id, default: 0],
                  currencyCode: currencyCode,
                  onSelectTransaction: onSelectTransaction
                )
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: kind.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
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
        }
      }

      Section {
        Button("Add Account", systemImage: "plus", action: onAddAccount)
      }
    }
    .navigationTitle("Accounts")
  }
}

private struct AccountDetailScreen: View {
  var account: BudgetAccount
  var transactions: [BudgetTransaction]
  var balanceMinor: Int64
  var currencyCode: String
  var onSelectTransaction: (UUID) -> Void

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
  }
}
