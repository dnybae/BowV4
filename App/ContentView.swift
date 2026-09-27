import SwiftUI
import SwiftData

struct ContentView: View {
  @Query private var profiles: [BudgetProfile]
  @Query private var accounts: [BudgetAccount]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var allocations: [BudgetAllocation]
  @Query private var transactions: [BudgetTransaction]
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @State private var selectedMonth = Date()
  @State private var selectedTab: BowTab = .budget
  @State private var activeSheet: BowSheet?
  @State private var showingSettings = false

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  private var snapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: selectedMonth,
      accounts: accounts,
      envelopes: envelopes,
      allocations: allocations,
      transactions: transactions
    )
  }

  private var currentSnapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: Date(),
      accounts: accounts,
      envelopes: envelopes,
      allocations: allocations,
      transactions: transactions
    )
  }

  var body: some View {
    Group {
      if profiles.isEmpty {
        WelcomeScreen()
      } else {
        TabView(selection: $selectedTab) {
          Tab("Budget", systemImage: "square.grid.2x2.fill", value: BowTab.budget) {
            NavigationStack {
              BudgetScreen(
                currencyCode: currencyCode,
                groups: groups,
                envelopes: envelopes,
                accounts: accounts,
                snapshot: snapshot,
                selectedMonth: $selectedMonth,
                onAddAccount: { activeSheet = .newAccount },
                onAddGroup: { activeSheet = .newGroup },
                onAddEnvelope: { activeSheet = .newEnvelope },
                onImportYNAB: { activeSheet = .importYNAB },
                onMoveMoney: { source, target in
                  activeSheet = .moveMoney(source, target)
                }
              )
              .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
              }
            }
          }
          Tab("Transactions", systemImage: "list.bullet.rectangle", value: BowTab.transactions) {
            NavigationStack {
              TransactionsScreen(
                transactions: transactions,
                accounts: accounts,
                envelopes: envelopes,
                currencyCode: currencyCode,
                onSelect: { activeSheet = .editTransaction($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
              }
            }
          }
          Tab("Accounts", systemImage: "banknote.fill", value: BowTab.accounts) {
            NavigationStack {
              AccountsScreen(
                accounts: accounts,
                transactions: transactions,
                snapshot: currentSnapshot,
                currencyCode: currencyCode,
                onAddAccount: { activeSheet = .newAccount },
                onSelectTransaction: { activeSheet = .editTransaction($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
              }
            }
          }
        }
        .tint(Color.accentColor)
        .sheet(isPresented: $showingSettings) {
          SettingsScreen {
            showingSettings = false
            selectedTab = .accounts
          }
        }
        .sheet(item: $activeSheet) { sheet in
          switch sheet {
          case .newTransaction:
            TransactionEditorScreen(
              transaction: nil,
              accounts: accounts,
              envelopes: envelopes,
              currencyCode: currencyCode
            )
          case .editTransaction(let id):
            TransactionEditorScreen(
              transaction: transactions.first { $0.id == id },
              accounts: accounts,
              envelopes: envelopes,
              currencyCode: currencyCode
            )
          case .newAccount:
            AccountEditorScreen(currencyCode: currencyCode)
          case .newGroup:
            GroupEditorScreen(nextOrder: groups.count)
          case .newEnvelope:
            EnvelopeEditorScreen(groups: groups, nextOrder: envelopes.count)
          case .importYNAB:
            YNABImportScreen(groups: groups, envelopes: envelopes)
          case .moveMoney(let source, let target):
            MoneyMoveScreen(
              accounts: accounts,
              envelopes: envelopes,
              snapshot: snapshot,
              currencyCode: currencyCode,
              month: selectedMonth,
              source: source,
              target: target
            )
          }
        }
      }
    }
    .preferredColorScheme(
      AppAppearance(rawValue: appearanceRaw)?.colorScheme
    )
  }
}

private enum BowTab: Hashable {
  case budget
  case transactions
  case accounts
}

private enum BowSheet: Identifiable {
  case newTransaction
  case editTransaction(UUID)
  case newAccount
  case newGroup
  case newEnvelope
  case importYNAB
  case moveMoney(BudgetBucket, BudgetBucket)

  var id: String {
    switch self {
    case .newTransaction: "newTransaction"
    case .editTransaction(let id): "editTransaction-\(id)"
    case .newAccount: "newAccount"
    case .newGroup: "newGroup"
    case .newEnvelope: "newEnvelope"
    case .importYNAB: "importYNAB"
    case .moveMoney: "moveMoney"
    }
  }
}
