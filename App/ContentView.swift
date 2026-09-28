import SwiftUI
import SwiftData

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Query private var profiles: [BudgetProfile]
  @Query private var accounts: [BudgetAccount]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var payees: [BudgetPayee]
  @Query private var allocations: [BudgetAllocation]
  @Query private var transactions: [BudgetTransaction]
  @Query private var schedules: [BudgetSchedule]
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @State private var selectedMonth = Date()
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
        TabView {
          Tab("Budget", systemImage: "square.grid.2x2.fill") {
            NavigationStack {
              BudgetScreen(
                currencyCode: currencyCode,
                groups: groups,
                envelopes: envelopes,
                accounts: accounts,
                snapshot: snapshot,
                selectedMonth: $selectedMonth,
                onAddGroup: { activeSheet = .newGroup },
                onAddEnvelope: { activeSheet = .newEnvelope },
                onImportYNAB: { activeSheet = .importYNAB },
                onMoveMoney: { source, target in
                  activeSheet = .moveMoney(source, target)
                }
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
              }
            }
          }
          Tab("Transactions", systemImage: "list.bullet.rectangle") {
            NavigationStack {
              TransactionsScreen(
                transactions: transactions,
                accounts: accounts,
                envelopes: envelopes,
                currencyCode: currencyCode,
                onSelect: { activeSheet = .editTransaction($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
              }
            }
          }
          Tab("Calendar", systemImage: "calendar") {
            NavigationStack {
              CalendarScreen(
                schedules: schedules,
                transactions: transactions,
                accounts: accounts,
                envelopes: envelopes,
                snapshot: currentSnapshot,
                currencyCode: currencyCode,
                onRecord: { activeSheet = .recordScheduled($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
              }
            }
          }
          Tab("Insights", systemImage: "chart.bar.fill") {
            NavigationStack {
              InsightsScreen(
                groups: groups,
                envelopes: envelopes,
                accounts: accounts,
                allocations: allocations,
                transactions: transactions,
                currencyCode: currencyCode
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") { activeSheet = .newTransaction }
                }
              }
            }
          }
          Tab("Accounts", systemImage: "banknote.fill") {
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
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Add Transaction", systemImage: "plus") {
                    activeSheet = .newTransaction
                  }
                }
              }
            }
          }
        }
        .tint(Color.accentColor)
        .sheet(isPresented: $showingSettings) {
          SettingsScreen()
        }
        .sheet(item: $activeSheet) { sheet in
          switch sheet {
          case .newTransaction:
            TransactionEditorScreen(
              transaction: nil,
              accounts: accounts,
              envelopes: envelopes,
              payees: payees,
              currencyCode: currencyCode
            )
          case .editTransaction(let id):
            TransactionEditorScreen(
              transaction: transactions.first { $0.id == id },
              accounts: accounts,
              envelopes: envelopes,
              payees: payees,
              currencyCode: currencyCode
            )
          case .recordScheduled(let draft):
            TransactionEditorScreen(
              transaction: nil,
              accounts: accounts,
              envelopes: envelopes,
              payees: payees,
              currencyCode: currencyCode,
              scheduledDraft: draft
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
    .task { await refreshSimpleFINIfConnected() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await refreshSimpleFINIfConnected() }
      } else if phase == .background {
        SimpleFINBackgroundRefresh.schedule(in: modelContext)
      }
    }
  }

  private func refreshSimpleFINIfConnected() async {
    guard (try? SimpleFINCredentialStore().load()) != nil else { return }
    _ = try? await SimpleFINSyncCoordinator.shared.sync(in: modelContext)
  }
}

private enum BowSheet: Identifiable {
  case newTransaction
  case editTransaction(UUID)
  case recordScheduled(ScheduledTransactionDraft)
  case newAccount
  case newGroup
  case newEnvelope
  case importYNAB
  case moveMoney(BudgetBucket, BudgetBucket)

  var id: String {
    switch self {
    case .newTransaction: "newTransaction"
    case .editTransaction(let id): "editTransaction-\(id)"
    case .recordScheduled(let draft): "recordScheduled-\(draft.scheduleID)-\(draft.scheduledFor)"
    case .newAccount: "newAccount"
    case .newGroup: "newGroup"
    case .newEnvelope: "newEnvelope"
    case .importYNAB: "importYNAB"
    case .moveMoney: "moveMoney"
    }
  }
}
