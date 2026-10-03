import SwiftUI
import SwiftData

struct SimpleFINAccountSetupScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var connections: [SimpleFINConnection]
  @Query private var links: [SimpleFINAccountLink]
  @Query private var accounts: [BudgetAccount]
  @Query private var profiles: [BudgetProfile]
  var isDemoMode = false
  var onDone: (() -> Void)?

  @State private var setupToken = ""
  @State private var selectedKeys = Set<String>()
  @State private var accountTypes: [String: BudgetAccountType] = [:]
  @State private var balanceDrafts: [String: Int64] = [:]
  @State private var initializedKeys = Set<String>()
  @State private var importHistory = false
  @State private var historyStart = Date().addingTimeInterval(-SimpleFINSyncCoordinator.historyWindow)
  @State private var isWorking = false
  @State private var needsToken = false
  @State private var message: String?

  private var connection: SimpleFINConnection? { connections.first }
  private var allLinks: [SimpleFINAccountLink] {
    links.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  private var availableLinks: [SimpleFINAccountLink] {
    allLinks.filter { $0.localAccountID == nil }
  }
  private var linkedLinks: [SimpleFINAccountLink] {
    allLinks.filter { $0.localAccountID != nil }
  }
  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var selectedLinks: [SimpleFINAccountLink] {
    availableLinks.filter { selectedKeys.contains($0.remoteKey) }
  }
  private var canAdd: Bool {
    !selectedLinks.isEmpty && selectedLinks.allSatisfy { link in
      let balance = balanceDrafts[link.remoteKey, default: 0]
      let type = accountTypes[link.remoteKey] ?? .checking
      return link.currencyCode == currencyCode
        && !link.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (type.kind != .liability || balance <= 0)
    }
  }

  var body: some View {
    Form {
      if isDemoMode && connection == nil {
        ContentUnavailableView(
          "No sample connection", systemImage: "link",
          description: Text("Choose Sample Budget in Settings to explore bank accounts.")
        )
      } else if connection == nil || needsToken {
        Section {
          Text(needsToken
            ? "Enter a new SimpleFIN setup token to restore your bank connection."
            : "Connect SimpleFIN to see the bank accounts you can add to Bow.")
            .foregroundStyle(Bow.inkSoft)
          Link("Get a SimpleFIN setup token", destination: URL(string: "https://bridge.simplefin.org/simplefin/create")!)
          SecureField("Setup token", text: $setupToken)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
          Button("Continue", systemImage: "arrow.right") {
            Task { await connect() }
          }
          .disabled(setupToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        } header: {
          Text("Connect your bank")
        } footer: {
          Text("SimpleFIN is read-only and has a separate signup and fee. Bank updates may arrive about once a day.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
      } else {
        if allLinks.isEmpty {
          if isWorking {
            BowLoadingLabel("Loading your bank accounts…")
              .frame(maxWidth: .infinity)
              .listRowBackground(Color.clear)
          } else {
            ContentUnavailableView(
              "No bank accounts found", systemImage: "link",
              description: Text("Check your SimpleFIN connection, then refresh the account list.")
            )
            .listRowBackground(Color.clear)
          }
        }

        ForEach(availableLinks) { link in
          Section {
            newAccountRows(link)
          } header: {
            if link.id == availableLinks.first?.id {
              Text("New at your bank")
            }
          } footer: {
            if link.id == availableLinks.last?.id {
              Text("Checking, savings, and credit cards are on your budget. Investments and loans count toward net worth only.")
                .font(.bowFootnote)
            }
          }
          .listRowBackground(Bow.card)
        }

        if !availableLinks.isEmpty && !isDemoMode {
          Section {
            Toggle(isOn: $importHistory) {
              Label("Import past transactions", systemImage: "clock.arrow.circlepath").labelStyle(.bowTile)
            }
            if importHistory {
              BowDateRow(title: "From", systemImage: "calendar", date: $historyStart,
                         range: Date().addingTimeInterval(-SimpleFINSyncCoordinator.historyWindow)...Date())
            }
          } footer: {
            Text(importHistory
              ? "Bow can bring in up to 45 days of history, and adjusts each starting balance so it isn’t counted twice."
              : "Each account starts at the bank’s latest balance, and new activity comes in from now on.")
              .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        }

        if !linkedLinks.isEmpty {
          Section {
            ForEach(linkedLinks) { link in
              linkedAccountRow(link)
            }
          } header: {
            Text("Already in Bow")
          } footer: {
            if isDemoMode {
              Text("Sample accounts. No bank is contacted.")
                .font(.bowFootnote)
            } else if let lastCheck = connection?.lastAttemptAt {
              Text("Checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                .font(.bowFootnote)
            }
          }
          .listRowBackground(Bow.card)
        }
      }
    }
    .bowListBackground()
    .navigationTitle((connection == nil || needsToken) && !isDemoMode ? "Connect a bank" : "Bank accounts")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard !isDemoMode, let connection else { return }
      do {
        guard try SimpleFINCredentialStore().load() != nil else {
          needsToken = true
          return
        }
        if let lastCheck = connection.lastAttemptAt,
           Date().timeIntervalSince(lastCheck) < 10 * 60 { return }
        await refreshAccounts()
      } catch {
        message = error.localizedDescription
      }
    }
    .task(id: availableLinks.map(\.remoteKey)) {
      let suggester = SimpleFINAccountTypeSuggester()
      // On first setup every account starts selected. Coming back later, accounts left out
      // before were skipped on purpose, so nothing is preselected.
      let isFirstSetup = linkedLinks.isEmpty
      for link in availableLinks where !initializedKeys.contains(link.remoteKey) {
        initializedKeys.insert(link.remoteKey)
        if isFirstSetup && link.currencyCode == currencyCode {
          selectedKeys.insert(link.remoteKey)
        }
        accountTypes[link.remoteKey] = suggester.type(for: link.name)
        balanceDrafts[link.remoteKey] = link.reportedBalance.flatMap {
          BudgetMoney.parseMinor($0, locale: Locale(identifier: "en_US_POSIX"))
        } ?? 0
      }
    }
    .toolbar {
      if connection != nil && !needsToken && !isDemoMode {
        ToolbarItem(placement: .topBarTrailing) {
          if isWorking {
            ProgressView()
          } else {
            Button("Refresh Bank Accounts", systemImage: "arrow.clockwise") {
              Task { await refreshAccounts() }
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if connection != nil && !needsToken && !availableLinks.isEmpty {
        BowBottomAction(isEnabled: canAdd && !isWorking, action: { Task { await addAccounts() } }) {
          Text(isWorking ? "Adding…"
            : selectedLinks.isEmpty ? "Choose Accounts to Add"
            : "Add \(selectedLinks.count) \(selectedLinks.count == 1 ? "Account" : "Accounts")")
        }
      }
    }
    .bowErrorAlert("SimpleFIN", message: $message)
  }

  /// An account at the bank that isn't in Bow yet: a toggle, then its type and starting balance.
  @ViewBuilder
  private func newAccountRows(_ link: SimpleFINAccountLink) -> some View {
    let key = link.remoteKey
    let currencyMatches = link.currencyCode == currencyCode
    let isSelected = selectedKeys.contains(key)
    Toggle(isOn: Binding(
      get: { selectedKeys.contains(key) },
      set: { selected in
        if selected { selectedKeys.insert(key) }
        else { selectedKeys.remove(key) }
      }
    )) {
      HStack(spacing: Bow.Space.s3) {
        AccountLogoView(appearance: link.logoAppearance, size: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text(link.name)
            .lineLimit(2)
          Text(bankBalance(link))
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
        }
      }
    }
    .disabled(!currencyMatches)
    if !currencyMatches {
      Text("This account uses \(link.currencyCode); this budget uses \(currencyCode).")
        .font(.bowFootnote).foregroundStyle(Bow.inkSoft)
    } else if isSelected {
      let type = accountTypes[key] ?? .checking
      Picker(selection: Binding(
        get: { accountTypes[key] ?? .checking },
        set: { accountTypes[key] = $0 }
      )) {
        AccountTypeMenu()
      } label: {
        Label("Type", systemImage: type.systemImage).labelStyle(.bowTile)
      }
      .pickerStyle(.menu)
      CurrencyAmountField("Starting balance", minor: Binding(
        get: { balanceDrafts[key, default: 0] },
        set: { balanceDrafts[key] = $0 }
      ), currencyCode: currencyCode, allowsNegative: true, systemImage: "dollarsign")
      if type.kind == .liability, balanceDrafts[key, default: 0] > 0 {
        Text("Enter money owed as a negative balance.")
          .font(.bowFootnote).foregroundStyle(Bow.needs)
      }
    }
  }

  /// An account already syncing into Bow: its Bow name, with the bank's balance trailing.
  private func linkedAccountRow(_ link: SimpleFINAccountLink) -> some View {
    let account = accounts.first { $0.id == link.localAccountID }
    let name = account?.name ?? link.name
    return HStack(spacing: Bow.Space.s3) {
      AccountLogoView(appearance: account?.logoAppearance ?? link.logoAppearance, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .lineLimit(2)
        // The bank's name only when it was renamed in Bow, so it's still recognizable.
        if name != link.name {
          Text(link.name)
            .font(.bowSubhead).foregroundStyle(Bow.inkSoft)
            .lineLimit(1)
        }
      }
      .layoutPriority(1)
      Spacer(minLength: Bow.Space.s2)
      if let reported = link.reportedBalance {
        Text(BudgetMoney.formatted(bankAmount: reported, currencyCode: link.currencyCode))
          .font(.bowSubhead.monospacedDigit())
          .foregroundStyle(Bow.inkSoft)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func bankBalance(_ link: SimpleFINAccountLink) -> String {
    link.reportedBalance.map {
      "Bank balance \(BudgetMoney.formatted(bankAmount: $0, currencyCode: link.currencyCode))"
    } ?? "Balance unavailable"
  }

  private func connect() async {
    isWorking = true
    defer { isWorking = false }
    do {
      try await SimpleFINSyncCoordinator.shared.connect(token: setupToken, in: modelContext)
      setupToken = ""
      needsToken = false
    } catch {
      setupToken = ""
      message = error.localizedDescription
    }
  }

  private func addAccounts() async {
    guard let connection, canAdd else { return }
    isWorking = true
    defer { isWorking = false }
    let startDate = importHistory ? Calendar.current.startOfDay(for: historyStart) : Date()
    var accountsAdded = false
    var createdCount = 0
    var created: [(BudgetAccount, Int64)] = []
    do {
      let selectedDrafts = try selectedLinks.map { link -> (SimpleFINAccountLink, Int64, BudgetAccountType) in
        let balance = balanceDrafts[link.remoteKey, default: 0]
        let type = accountTypes[link.remoteKey] ?? .checking
        guard type.kind != .liability || balance <= 0 else {
          throw BudgetCommandError.liabilityRequiresNegativeBalance
        }
        return (link, balance, type)
      }
      for (link, balance, type) in selectedDrafts {
        let account = try BudgetCommands.addAccount(
          name: link.name, kind: type.kind, currencyCode: link.currencyCode,
          openingBalanceMinor: balance, type: type, in: modelContext
        )
        createdCount += 1
        created.append((account, balance))
        link.applyInstitution(to: account)
        link.localAccountID = account.id
        link.importStartDate = startDate
      }
      connection.lastMappingChangeAt = Date()
      try modelContext.save()
      accountsAdded = true
      if !isDemoMode {
        _ = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
        // The bank's balance already includes what posted today, and today's items now count
        // in the ledger, so the starting balance is set to keep each account at the bank's figure.
        for (account, balance) in created {
          try BudgetCommands.moveStartingBalanceDate(
            of: account, to: account.openedAt, keepingBalance: balance, in: modelContext
          )
        }
        try modelContext.save()
        SimpleFINBackgroundRefresh.schedule(in: modelContext)
      }
      if let onDone { onDone() } else { dismiss() }
    } catch {
      message = accountsAdded
        ? "Your accounts were added, but the first sync could not finish. Try Sync Now in Settings → SimpleFIN. \(error.localizedDescription)"
        : createdCount > 0
          ? "\(createdCount) \(createdCount == 1 ? "account was" : "accounts were") created before setup stopped. Check Accounts before retrying. \(error.localizedDescription)"
          : error.localizedDescription
    }
  }

  private func refreshAccounts() async {
    isWorking = true
    defer { isWorking = false }
    do {
      _ = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
    } catch {
      message = error.localizedDescription
    }
  }
}

struct SimpleFINAccountTypeSuggester {
  func type(for name: String) -> BudgetAccountType {
    let value = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    if ["credit card", "visa", "mastercard", "amex"].contains(where: value.contains) {
      return .creditCard
    }
    if ["loan", "mortgage"].contains(where: value.contains) { return .loan }
    if ["ira", "roth", "crypto", "invest", "brokerage", "retirement", "401k", "stock"].contains(where: value.contains) {
      return .investment
    }
    if value.contains("savings") { return .savings }
    // Most accounts a bank sync finds are everyday deposit accounts.
    return .checking
  }
}
