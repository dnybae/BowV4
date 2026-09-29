import SwiftUI
import SwiftData

struct SimpleFINAccountSetupScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var connections: [SimpleFINConnection]
  @Query private var links: [SimpleFINAccountLink]
  @Query private var profiles: [BudgetProfile]
  var onDone: (() -> Void)?

  @State private var setupToken = ""
  @State private var selectedKeys = Set<String>()
  @State private var accountTypes: [String: BudgetAccountType] = [:]
  @State private var balanceDrafts: [String: String] = [:]
  @State private var initializedKeys = Set<String>()
  @State private var importHistory = false
  @State private var historyStart = Date().addingTimeInterval(-89 * 86_400)
  @State private var isWorking = false
  @State private var message: String?

  private var connection: SimpleFINConnection? { connections.first }
  private var availableLinks: [SimpleFINAccountLink] {
    links.filter { $0.localAccountID == nil }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var selectedLinks: [SimpleFINAccountLink] {
    availableLinks.filter { selectedKeys.contains($0.remoteKey) }
  }
  private var canAdd: Bool {
    !selectedLinks.isEmpty && selectedLinks.allSatisfy { link in
      let balance = BudgetMoney.parseMinor(balanceDrafts[link.remoteKey] ?? "")
      let type = accountTypes[link.remoteKey] ?? .other
      return link.currencyCode == currencyCode
        && !link.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && balance != nil
        && (type.kind != .liability || (balance ?? 0) <= 0)
    }
  }

  var body: some View {
    Form {
      if connection == nil {
        Section {
          Text("Connect SimpleFIN to see the bank accounts you can add to Bow.")
            .foregroundStyle(.secondary)
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
      } else if availableLinks.isEmpty {
        Section {
          ContentUnavailableView(
            "No New Bank Accounts", systemImage: "checkmark",
            description: Text("Connect another account in SimpleFIN, then refresh to find it here.")
          )
          Button("Refresh Bank Accounts", systemImage: "arrow.clockwise") {
            Task { await refreshAccounts() }
          }
          .disabled(isWorking)
        }
      } else {
        Section {
          Text("Choose the accounts to add. Bow will create a matching account for each selection and connect its bank updates automatically.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          ForEach(availableLinks) { link in
            accountRow(link)
          }
        } header: {
          Text("Accounts found in SimpleFIN")
        } footer: {
          Text("Checking, savings, and credit cards affect your budget. Investments and loans are tracked in net worth.")
        }

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

        Section {
          Button("Add \(selectedLinks.count) \(selectedLinks.count == 1 ? "Account" : "Accounts")") {
            Task { await addAccounts() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canAdd || isWorking)
          if isWorking { ProgressView("Adding accounts…") }
        }
      }
    }
    .navigationTitle(connection == nil ? "Connect a Bank" : "Choose Bank Accounts")
    .navigationBarTitleDisplayMode(.inline)
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
        }.map(BudgetMoney.editableSigned) ?? ""
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
            Text("Bank-reported balance: \(reported) \(link.currencyCode)")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("Balance unavailable")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .disabled(link.currencyCode != currencyCode)
      if link.currencyCode != currencyCode {
        Text("This account uses \(link.currencyCode); this Bow budget uses \(currencyCode).")
          .font(.footnote).foregroundStyle(.secondary)
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
          .font(.caption).foregroundStyle(.secondary)
        TextField("Starting balance", text: Binding(
          get: { balanceDrafts[key] ?? "" },
          set: { balanceDrafts[key] = $0 }
        ))
        .keyboardType(.numbersAndPunctuation)
        if (accountTypes[key] ?? .other).kind == .liability,
           (BudgetMoney.parseMinor(balanceDrafts[key] ?? "") ?? 0) > 0 {
          Text("Enter money owed as a negative balance.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func connect() async {
    isWorking = true
    defer { isWorking = false }
    do {
      try await SimpleFINSyncCoordinator.shared.connect(token: setupToken, in: modelContext)
      setupToken = ""
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
        guard let balance = BudgetMoney.parseMinor(balanceDrafts[link.remoteKey] ?? "")
        else { throw SimpleFINError.invalidAmount }
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
      _ = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
      SimpleFINBackgroundRefresh.schedule(in: modelContext)
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
