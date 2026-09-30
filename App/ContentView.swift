import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
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
    .bowAppTint()
    .task(id: isDemoMode) {
      if isDemoMode && demoContainer == nil { prepareDemo() }
    }
    .onChange(of: appearanceRaw, initial: true) { _, raw in
      AppAppearanceController.apply(AppAppearance(rawValue: raw) ?? .system)
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var profiles: [BudgetProfile]
  @Query private var accounts: [BudgetAccount]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var payees: [BudgetPayee]
  @Query private var allocations: [BudgetAllocation]
  @Query private var schedules: [BudgetSchedule]
  @Query private var scheduleOccurrences: [BudgetScheduleOccurrence]
  @State private var snapshotRepository: BudgetSnapshotRepository?
  @State private var loadedSnapshot: BudgetSnapshot?
  @State private var loadedPreviousSnapshot: BudgetSnapshot?
  @State private var loadedAccountReport: AccountBalanceReport?
  @State private var ledgerError: String?
  @State private var ledgerRefreshGeneration = 0
  @State private var selectedMonth = Date()
  @State private var selectedCalendarDate = Date()
  @State private var selectedTab: HomeTab = .budget
  @State private var budgetPath: [BudgetRoute] = []
  @State private var accountsPath: [AccountRoute] = []
  @State private var budgetReturnToPresentRequest = 0
  @State private var calendarReturnToTodayRequest = 0
  @State private var activeSheet: BowSheet?
  @State private var showingSettings = false
  @State private var showingInsights = false
  @State private var lastKnownCurrentMonth = Date()

  private static let addTransactionTabTitle = "Add Transaction"

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  /// The month the Budget screen is showing. Actions act on what the user sees,
  /// even in the moment before a newly selected month finishes loading.
  private var displayedBudgetMonth: Date {
    let month = loadedSnapshot?.month ?? selectedMonth
    return Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
  }

  private var accountsTabSymbol: String {
    if #available(iOS 27.0, *) {
      "building.classical.columns.fill"
    } else {
      "building.columns.fill"
    }
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
            } else if tab == selectedTab {
              switch tab {
              case .budget:
                budgetPath.removeAll()
                budgetReturnToPresentRequest += 1
              case .calendar:
                calendarReturnToTodayRequest += 1
              case .transactions, .accounts, .addTransaction:
                break
              }
            } else {
              selectedTab = tab
            }
          }
        )) {
          Tab("Budget", systemImage: "square.grid.2x2.fill", value: .budget) {
            NavigationStack(path: $budgetPath) {
              Group {
              // Keep showing the last loaded month while the next one calculates, so the
              // screen stays in place and its numbers roll to the new month.
              if let snapshot = loadedSnapshot, ledgerError == nil {
                BudgetScreen(
                currencyCode: currencyCode,
                groups: groups,
                envelopes: envelopes,
                accounts: accounts,
                allocations: allocations,
                schedules: schedules,
                snapshot: snapshot,
                previousSnapshot: loadedPreviousSnapshot,
                selectedMonth: $selectedMonth,
                returnToPresentRequest: budgetReturnToPresentRequest,
                onAddGroup: { activeSheet = .newGroup },
                onAddEnvelope: { activeSheet = .newEnvelope },
                onEditEnvelope: { activeSheet = .editEnvelope($0) },
                onImportYNAB: { activeSheet = .importYNAB },
                onMoveMoney: { source, target in
                  activeSheet = .moveMoney(source, target, displayedBudgetMonth)
                },
                onCoverOverspending: { scope in
                  activeSheet = .coverOverspending(displayedBudgetMonth, scope)
                },
                onSelectTransaction: { activeSheet = .editTransaction($0) },
                onEditSchedule: { activeSheet = .editSchedule($0) }
                )
              } else {
                if let ledgerError {
                  ContentUnavailableView("Budget Unavailable", systemImage: "exclamationmark.triangle",
                                         description: Text(ledgerError))
                } else {
                  ProgressView("Calculating budget…")
                }
              }
              }
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
              }
            }
            .background {
              AddTabInterceptor(tabTitle: Self.addTransactionTabTitle) {
                activeSheet = .newTransaction
              }
            }
          }
          Tab("Spending", systemImage: "list.bullet.rectangle", value: .transactions) {
            NavigationStack {
              TransactionsScreen(
                accounts: accounts,
                envelopes: envelopes,
                schedules: schedules,
                occurrences: scheduleOccurrences,
                currencyCode: currencyCode,
                onSelect: { activeSheet = .transactionDetail($0) },
                onRecord: { activeSheet = .recordScheduled($0) },
                onEditSchedule: { activeSheet = .editSchedule($0) }
              )
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
              }
            }
          }
          Tab("Calendar", systemImage: "calendar", value: .calendar) {
            NavigationStack {
              CalendarScreen(
                schedules: schedules,
                occurrences: scheduleOccurrences,
                accounts: accounts,
                envelopes: envelopes,
                currencyCode: currencyCode,
                selectedDate: $selectedCalendarDate,
                returnToTodayRequest: calendarReturnToTodayRequest,
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
            NavigationStack(path: $accountsPath) {
              Group {
              if let currentAccountReport = loadedAccountReport {
                AccountsScreen(
                accounts: accounts,
                balanceReport: currentAccountReport,
                currencyCode: currencyCode,
                onAddAccount: { activeSheet = .newAccount },
                onViewInsights: { showingInsights = true },
                onSelectTransaction: { activeSheet = .editTransaction($0) }
                )
              } else {
                if let ledgerError {
                  ContentUnavailableView("Balances Unavailable", systemImage: "exclamationmark.triangle",
                                         description: Text(ledgerError))
                } else {
                  ProgressView("Calculating balances…")
                }
              }
              }
              .navigationDestination(isPresented: $showingInsights) {
                insightsDestination
              }
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
              }
            }
          }
          if #available(iOS 27.0, *) {
            Tab(Self.addTransactionTabTitle, systemImage: "plus", value: .addTransaction, role: .prominent) {
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
        .bowAppTint()
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
              transaction: transaction(for: id),
              accounts: accounts,
              envelopes: envelopes,
              payees: payees,
              currencyCode: currencyCode
            )
          case .transactionDetail(let id):
            if let transaction = transaction(for: id) {
              TransactionDetailScreen(
                transaction: transaction,
                accounts: accounts, envelopes: envelopes,
                payees: payees, currencyCode: currencyCode
              )
            }
          case .recordScheduled(let draft):
            TransactionEditorScreen(
              transaction: nil,
              accounts: accounts,
              envelopes: envelopes,
              payees: payees,
              currencyCode: currencyCode,
              scheduledDraft: draft
            )
          case .editSchedule(let id):
            ScheduleEditorScreen(
              schedule: schedules.first { $0.id == id },
              accounts: accounts, envelopes: envelopes, currencyCode: currencyCode
            )
          case .newAccount:
            AddAccountFlowScreen(currencyCode: currencyCode, isDemoMode: isDemoMode)
          case .newGroup:
            GroupEditorScreen(nextOrder: groups.count)
          case .newEnvelope:
            EnvelopeEditorScreen(groups: groups.filter { !$0.isSystem }, nextOrder: envelopes.count)
          case .editEnvelope(let id):
            EnvelopeEditorScreen(
              groups: groups.filter { !$0.isSystem },
              nextOrder: envelopes.count,
              envelope: envelopes.first { $0.id == id }
            )
          case .importYNAB:
            YNABImportScreen(groups: groups, envelopes: envelopes)
          case .moveMoney(let source, let target, let month):
            MoneyMoveScreen(
              currencyCode: currencyCode,
              month: month,
              source: source,
              target: target
            )
          case .coverOverspending(let month, let scope):
            CoverOverspendingScreen(currencyCode: currencyCode, month: month, scope: scope)
          }
        }
      }
    }
    .environment(\.budgetSnapshotRepository, snapshotRepository)
    .environment(\.payeeLogoDirectory, PayeeLogoDirectory(payees: payees))
    .task {
      try? BudgetCommands.ensureCardPaymentEnvelopes(in: modelContext)
      try? ScheduleReviewPlanner().refresh(in: modelContext)
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      if !isDemoMode { await refreshSimpleFINIfConnected() }
    }
    .task(id: Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth) {
      await refreshLedger()
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      Task { await refreshLedger(invalidate: true) }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { try? ScheduleTargetSynchronizer().refresh(in: modelContext) }
      guard !isDemoMode else { return }
      if phase == .active {
        try? ScheduleReviewPlanner().refresh(in: modelContext)
        Task { await refreshSimpleFINIfConnected() }
      } else if phase == .background {
        SimpleFINBackgroundRefresh.schedule(in: modelContext)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
      try? ScheduleReviewPlanner().refresh(in: modelContext)
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      let calendar = Calendar.current
      if calendar.isDate(selectedMonth, equalTo: lastKnownCurrentMonth, toGranularity: .month) {
        selectedMonth = Date()
      }
      if calendar.isDate(selectedCalendarDate, inSameDayAs: lastKnownCurrentMonth) {
        selectedCalendarDate = Date()
        calendarReturnToTodayRequest += 1
      }
      lastKnownCurrentMonth = Date()
    }
  }

  private func refreshSimpleFINIfConnected() async {
    guard (try? SimpleFINCredentialStore().load()) != nil else { return }
    _ = try? await SimpleFINSyncCoordinator.shared.sync(in: modelContext)
  }

  private func transaction(for id: UUID) -> BudgetTransaction? {
    let predicate = #Predicate<BudgetTransaction> { $0.id == id }
    var descriptor = FetchDescriptor<BudgetTransaction>(predicate: predicate)
    descriptor.fetchLimit = 1
    return try? modelContext.fetch(descriptor).first
  }

  @ViewBuilder
  private var insightsDestination: some View {
    if let loadedAccountReport, let snapshotRepository {
      InsightsScreen(
        groups: groups, envelopes: envelopes, accounts: accounts,
        currentNetWorth: loadedAccountReport,
        snapshotRepository: snapshotRepository, schedules: schedules,
        currencyCode: currencyCode
      )
    } else {
      ProgressView("Preparing insights…")
    }
  }

  private func refreshLedger(invalidate: Bool = false) async {
    ledgerRefreshGeneration += 1
    let generation = ledgerRefreshGeneration
    if snapshotRepository == nil {
      snapshotRepository = BudgetSnapshotRepository(modelContainer: modelContext.container)
    }
    guard let snapshotRepository else { return }
    if invalidate { await snapshotRepository.invalidate() }
    let month = selectedMonth
    do {
      let result = try await snapshotRepository.bundle(month: month, currencyCode: currencyCode)
      guard !Task.isCancelled,
            generation == ledgerRefreshGeneration,
            Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) else { return }
      withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
        loadedSnapshot = result.current
        loadedPreviousSnapshot = result.previous
      }
      loadedAccountReport = result.accountReport
      ledgerError = nil
    } catch is CancellationError {
      return
    } catch {
      if generation == ledgerRefreshGeneration {
        ledgerError = error.localizedDescription
      }
    }
  }
}

private enum BowSheet: Identifiable {
  case newTransaction
  case editTransaction(UUID)
  case transactionDetail(UUID)
  case recordScheduled(ScheduledTransactionDraft)
  case editSchedule(UUID)
  case newAccount
  case newGroup
  case newEnvelope
  case editEnvelope(UUID)
  case importYNAB
  case moveMoney(BudgetBucket, BudgetBucket, Date)
  case coverOverspending(Date, CoverOverspendingScope)

  var id: String {
    switch self {
    case .newTransaction: "newTransaction"
    case .editTransaction(let id): "editTransaction-\(id)"
    case .transactionDetail(let id): "transactionDetail-\(id)"
    case .recordScheduled(let draft): "recordScheduled-\(draft.scheduleID)-\(draft.scheduledFor)"
    case .editSchedule(let id): "editSchedule-\(id)"
    case .newAccount: "newAccount"
    case .newGroup: "newGroup"
    case .newEnvelope: "newEnvelope"
    case .editEnvelope(let id): "editEnvelope-\(id)"
    case .importYNAB: "importYNAB"
    case .moveMoney: "moveMoney"
    case .coverOverspending: "coverOverspending"
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
