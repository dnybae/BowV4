import SwiftUI
import SwiftData

struct ContentView: View {
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @AppStorage("bow.demoResetVersion") private var demoResetVersion = 0
  @AppStorage("bow.demoScenario") private var demoScenarioRaw = DemoScenario.showcase.rawValue
  @State private var demoContainer: ModelContainer?
  @State private var demoError: String?

  var body: some View {
    Group {
      if isDemoMode {
        if let demoContainer {
          BudgetHomeView(isDemoMode: true)
            .modelContainer(demoContainer)
            .id("\(demoScenarioRaw)-\(demoResetVersion)")
        } else if let demoError {
          ContentUnavailableView {
            Label("Demo Unavailable", systemImage: "exclamationmark.triangle")
          } description: {
            Text(demoError)
          } actions: {
            Button("Return to My Budget") { isDemoMode = false }
          }
        } else {
          ProgressView("Preparing demo…")
        }
      } else {
        BudgetHomeView(isDemoMode: false)
      }
    }
    .task(id: isDemoMode) {
      if isDemoMode && demoContainer == nil { prepareDemo() }
    }
    .onChange(of: demoResetVersion) { _, _ in
      demoContainer = nil
      if isDemoMode { prepareDemo() }
    }
    .onChange(of: demoScenarioRaw) { _, _ in
      demoContainer = nil
      if isDemoMode { prepareDemo() }
    }
  }

  private func prepareDemo() {
    do {
      demoError = nil
      demoContainer = try DemoData.makeContainer(
        scenario: DemoScenario(rawValue: demoScenarioRaw) ?? .showcase
      )
    } catch {
      demoError = error.localizedDescription
    }
  }
}

private struct BudgetHomeView: View {
  var isDemoMode: Bool
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
  @State private var selectedTab: HomeTab = .budget
  @State private var activeSheet: BowSheet?
  @State private var showingSettings = false
  @State private var showingInsights = false

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  private var accountsTabSymbol: String {
    if #available(iOS 27.0, *) {
      "building.classical.columns.fill"
    } else {
      "building.columns.fill"
    }
  }

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
        let tabs = TabView(selection: Binding(
          get: { selectedTab },
          set: { tab in
            if tab == .addTransaction {
              activeSheet = .newTransaction
            } else {
              selectedTab = tab
            }
          }
        )) {
          Tab("Budget", systemImage: "square.grid.2x2.fill", value: .budget) {
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
                onEditEnvelope: { activeSheet = .editEnvelope($0) },
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
              }
            }
          }
          Tab("Spending", systemImage: "list.bullet.rectangle", value: .transactions) {
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
              }
            }
          }
          Tab("Calendar", systemImage: "calendar", value: .calendar) {
            NavigationStack {
              CalendarScreen(
                schedules: schedules,
                transactions: transactions,
                accounts: accounts,
                envelopes: envelopes,
                allocations: allocations,
                currencyCode: currencyCode,
                onRecord: { activeSheet = .recordScheduled($0) },
                onSelectTransaction: { activeSheet = .editTransaction($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
              }
            }
          }
          Tab("Accounts", systemImage: accountsTabSymbol, value: .accounts) {
            NavigationStack {
              AccountsScreen(
                accounts: accounts,
                transactions: transactions,
                snapshot: currentSnapshot,
                currencyCode: currencyCode,
                onAddAccount: { activeSheet = .newAccount },
                onViewInsights: { showingInsights = true },
                onSelectTransaction: { activeSheet = .editTransaction($0) }
              )
              .navigationDestination(isPresented: $showingInsights) {
                InsightsScreen(
                  groups: groups,
                  envelopes: envelopes,
                  accounts: accounts,
                  allocations: allocations,
                  transactions: transactions,
                  currencyCode: currencyCode
                )
              }
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                  }
                }
              }
            }
          }
          if #available(iOS 27.0, *) {
            Tab("Add Transaction", systemImage: "plus", value: .addTransaction, role: .prominent) {
              EmptyView()
            }
          }
        }
        Group {
          if #available(iOS 27.0, *) {
            tabs
          } else {
            tabs.tabViewBottomAccessory {
              HStack {
                Spacer()
                Button("Add Transaction", systemImage: "plus") {
                  activeSheet = .newTransaction
                }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Add Transaction")
              }
              .padding(.horizontal, 16)
            }
          }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
          case .editEnvelope(let id):
            EnvelopeEditorScreen(
              groups: groups,
              nextOrder: envelopes.count,
              envelope: envelopes.first { $0.id == id }
            )
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
    .task { if !isDemoMode { await refreshSimpleFINIfConnected() } }
    .onChange(of: scenePhase) { _, phase in
      guard !isDemoMode else { return }
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
  case editEnvelope(UUID)
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
    case .editEnvelope(let id): "editEnvelope-\(id)"
    case .importYNAB: "importYNAB"
    case .moveMoney: "moveMoney"
    }
  }
}

private enum HomeTab: Hashable {
  case budget
  case transactions
  case calendar
  case accounts
  case addTransaction
}
