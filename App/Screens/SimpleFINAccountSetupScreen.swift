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
  @State private var historyStart = Date().addingTimeInterval(-89 * 86_400)
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
  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var selectedLinks: [SimpleFINAccountLink] {
    availableLinks.filter { selectedKeys.contains($0.remoteKey) }
  }
  private var canAdd: Bool {
    !selectedLinks.isEmpty && selectedLinks.allSatisfy { link in
      let balance = balanceDrafts[link.remoteKey, default: 0]
      let type = accountTypes[link.remoteKey] ?? .other
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
        }
        .listRowBackground(Bow.card)
      } else {
        Section {
          Text(isDemoMode
            ? "This sample connection shows accounts already in Bow and one you can add. No bank is contacted."
            : "These are the accounts found in your SimpleFIN connection. Select any new accounts to add to Bow.")
            .font(.subheadline)
            .foregroundStyle(Bow.inkSoft)
          if !isDemoMode {
            if let lastCheck = connection?.lastAttemptAt {
              Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(Bow.inkSoft)
            }
            Button("Refresh bank accounts", systemImage: "arrow.clockwise") {
              Task { await refreshAccounts() }
            }
            .disabled(isWorking)
          }
          if isWorking { ProgressView("Loading bank accounts…") }
          if allLinks.isEmpty && !isWorking {
            ContentUnavailableView(
              "No bank accounts found", systemImage: "link",
              description: Text("Check your SimpleFIN connection, then refresh the account list.")
            )
          }
          ForEach(allLinks) { link in
            accountRow(link)
          }
        } header: {
          Text("Accounts found in SimpleFIN")
        } footer: {
          Text("Accounts marked Already in Bow are already connected. Checking, savings, and credit cards affect your budget; investments and loans are tracked in net worth.")
        }
        .listRowBackground(Bow.card)

        if !availableLinks.isEmpty {
          if !isDemoMode {
            Section {
              Toggle("Import past transactions", isOn: $importHistory)
              if importHistory {
                DatePicker(
                  "From", selection: $historyStart,
                  in: Date().addingTimeInterval(-89 * 86_400)...Date(),
                  displayedComponents: .date
                )
              }
            } footer: {
              Text(importHistory
                ? "Bow can request up to 90 days of available history. It adjusts the starting balance so past activity is not counted twice."
                : "Bow starts with each bank’s latest reported balance and imports new activity from now on.")
            }
            .listRowBackground(Bow.card)
          }

          Section {
            Button {
              Task { await addAccounts() }
            } label: {
              Text("Add \(selectedLinks.count) \(selectedLinks.count == 1 ? "Account" : "Accounts")")
                .frame(maxWidth: .infinity)
            }
            .bowPrimaryButton()
            .disabled(!canAdd || isWorking)
            if isWorking { ProgressView("Adding accounts…") }
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
      for link in availableLinks where !initializedKeys.contains(link.remoteKey) {
        initializedKeys.insert(link.remoteKey)
        if link.currencyCode == currencyCode {
          selectedKeys.insert(link.remoteKey)
        }
        accountTypes[link.remoteKey] = suggester.type(for: link.name)
        balanceDrafts[link.remoteKey] = link.reportedBalance.flatMap {
          BudgetMoney.parseMinor($0, locale: Locale(identifier: "en_US_POSIX"))
        } ?? 0
      }
    }
    .alert("SimpleFIN", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  @ViewBuilder
  private func accountRow(_ link: SimpleFINAccountLink) -> some View {
    let key = link.remoteKey
    if let localID = link.localAccountID {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(link.name)
            .font(.body.weight(.medium))
          Text("Already in Bow as \(accounts.first { $0.id == localID }?.name ?? "an existing account")")
            .font(.subheadline)
            .foregroundStyle(Bow.inkSoft)
          if let reported = link.reportedBalance {
            Text("Bank-reported balance: \(BudgetMoney.formatted(bankAmount: reported, currencyCode: link.currencyCode))")
              .font(.caption)
              .foregroundStyle(Bow.inkSoft)
          }
        }
        Spacer(minLength: 0)
        Image(systemName: "checkmark")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 4)
      .accessibilityElement(children: .combine)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(isOn: Binding(
          get: { selectedKeys.contains(key) },
          set: { selected in
            if selected { selectedKeys.insert(key) }
            else { selectedKeys.remove(key) }
          }
        )) {
          VStack(alignment: .leading, spacing: 3) {
            Text(link.name)
            if let reported = link.reportedBalance {
              Text("Bank-reported balance: \(BudgetMoney.formatted(bankAmount: reported, currencyCode: link.currencyCode))")
                .font(.caption).foregroundStyle(Bow.inkSoft)
            } else {
              Text("Balance unavailable")
                .font(.caption).foregroundStyle(Bow.inkSoft)
            }
          }
        }
        .disabled(link.currencyCode != currencyCode)
        if link.currencyCode != currencyCode {
          Text("This account uses \(link.currencyCode); this Bow budget uses \(currencyCode).")
            .font(.footnote).foregroundStyle(Bow.inkSoft)
        } else if selectedKeys.contains(key) {
          Picker("Account type", selection: Binding(
            get: { accountTypes[key] ?? .other },
            set: { accountTypes[key] = $0 }
          )) {
            ForEach(BudgetAccountType.allCases) { type in
              Text(type.title).tag(type)
            }
          }
          .pickerStyle(.menu)
          Text((accountTypes[key] ?? .other).explanation)
            .font(.caption).foregroundStyle(Bow.inkSoft)
          LabeledContent("Starting balance") {
            CurrencyAmountField("Starting balance", minor: Binding(
              get: { balanceDrafts[key, default: 0] },
              set: { balanceDrafts[key] = $0 }
            ), currencyCode: currencyCode, allowsNegative: true)
            .labelsHidden()
          }
          if (accountTypes[key] ?? .other).kind == .liability,
             balanceDrafts[key, default: 0] > 0 {
            Text("Enter money owed as a negative balance.")
              .font(.footnote).foregroundStyle(Bow.inkSoft)
          }
        }
      }
      .padding(.vertical, 4)
    }
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
    do {
      let selectedDrafts = try selectedLinks.map { link -> (SimpleFINAccountLink, Int64, BudgetAccountType) in
        let balance = balanceDrafts[link.remoteKey, default: 0]
        let type = accountTypes[link.remoteKey] ?? .other
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
        link.localAccountID = account.id
        link.importStartDate = startDate
      }
      connection.lastMappingChangeAt = Date()
      try modelContext.save()
      accountsAdded = true
      if !isDemoMode {
        _ = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
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
    if value.contains("checking") { return .checking }
    return .other
  }
}
