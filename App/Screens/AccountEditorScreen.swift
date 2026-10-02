import SwiftUI
import SwiftData

struct AccountEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @Query private var simpleFINLinks: [SimpleFINAccountLink]
  @Query private var simpleFINConnections: [SimpleFINConnection]
  var currencyCode: String
  var account: BudgetAccount?
  /// Pushed inside Add Account: Back returns to the choice until something is typed.
  var isInFlow = false
  var onSaved: ((BudgetAccount) -> Void)?
  /// The account was deleted, so screens showing it should close.
  var onDeleted: (() -> Void)?
  @State private var name: String
  @State private var type: BudgetAccountType
  /// For debts, the amount owed as a positive number; otherwise the signed balance.
  @State private var amountMinor: Int64
  /// A credit card that's been overpaid carries a positive balance.
  @State private var isInCredit: Bool
  @State private var startDate: Date
  @State private var note: String
  @State private var logoSettings: AccountLogoSettings
  @State private var logoPresentation = AccountLogoPresentation()
  @State private var errorMessage: String?
  @State private var loadedCurrentBalance = false
  /// Today's balance and card payment money, for closing.
  @State private var currentBalanceMinor: Int64 = 0
  @State private var reservedMinor: Int64 = 0
  @State private var hasActivity = true
  @State private var showingBankLinkPicker = false
  @State private var showingStopBankSync = false
  @State private var showingClose = false
  @State private var showingDelete = false
  @State private var initialFields: AccountEditorFields?
  @State private var isSaving = false
  @Environment(\.bowToasts) private var toasts

  init(currencyCode: String, account: BudgetAccount? = nil,
       suggestedName: String = "", suggestedBalanceMinor: Int64? = nil,
       isInFlow: Bool = false,
       onSaved: ((BudgetAccount) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
    self.currencyCode = currencyCode
    self.account = account
    self.isInFlow = isInFlow
    self.onSaved = onSaved
    self.onDeleted = onDeleted
    let type = account?.accountType ?? .checking
    let balance = account?.openingBalanceMinor ?? suggestedBalanceMinor ?? 0
    _name = State(initialValue: account?.name ?? suggestedName)
    _type = State(initialValue: type)
    _amountMinor = State(initialValue: type.isDebt ? abs(balance) : balance)
    _isInCredit = State(initialValue: type.isDebt && balance > 0)
    _startDate = State(initialValue: account?.openedAt ?? Date())
    _note = State(initialValue: account?.note ?? "")
    _logoSettings = State(initialValue: account?.logoSettings ?? AccountLogoSettings())
  }

  private var signedBalance: Int64 {
    guard type.isDebt else { return amountMinor }
    return isInCredit && type == .creditCard ? amountMinor : -amountMinor
  }

  private var fields: AccountEditorFields {
    AccountEditorFields(name: name, type: type, balance: signedBalance,
                        startDay: BowDay.start(of: startDate), note: note, logoSettings: logoSettings)
  }

  private var hasChanges: Bool { initialFields.map { fields != $0 } ?? false }

  /// Before any activity, any type works; after, only types of the same kind.
  private var availableTypes: [BudgetAccountType] {
    guard let account, hasActivity else { return BudgetAccountType.allCases }
    return BudgetAccountType.allCases.filter { $0.kind == account.kind }
  }

  private var balanceTitle: String {
    if type.isDebt { return "Amount owed" }
    return account == nil ? "Starting balance" : "Balance"
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (account == nil || hasChanges)
  }

  var body: some View {
    Form {
      Section {
        BowNameHeader(placeholder: "Account name", name: $name) {
          AccountLogoView(appearance: logoSettings.appearance(
            institutionName: account?.institutionName, institutionDomain: account?.institutionDomain),
            systemImage: type.systemImage, size: 64, style: .glossy)
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      Section {
        if availableTypes.count > 1 {
          Picker(selection: $type) {
            AccountTypeMenu(types: availableTypes)
          } label: {
            Label("Type", systemImage: type.systemImage).labelStyle(.bowTile)
          }
          .pickerStyle(.menu)
        } else {
          BowTileValueRow("Type", systemImage: type.systemImage, value: type.title)
        }
        CurrencyAmountField(balanceTitle, minor: $amountMinor, currencyCode: currencyCode,
                            allowsNegative: !type.isDebt, systemImage: "dollarsign")
        if type == .creditCard {
          Toggle(isOn: $isInCredit) {
            Label("Card is in credit", systemImage: "plusminus").labelStyle(.bowTile)
          }
        }
        NavigationLink {
          BowDatePickerScreen(title: account == nil ? "Balance as of" : "Starting balance date",
                              date: $startDate, range: Date.distantPast...Date())
        } label: {
          BowTileValueRow(account == nil ? "Balance as of" : "Starting balance date", systemImage: "calendar",
                          value: startDate.formatted(date: .abbreviated, time: .omitted))
        }
        BowNotesRow(notes: $note)
      } footer: {
        Text(footerText)
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)

      AccountLogoControls(settings: $logoSettings, presentation: $logoPresentation,
                          institutionName: account?.institutionName,
                          institutionDomain: account?.institutionDomain)

      if let account, !isDemoMode, !simpleFINConnections.isEmpty, account.closedAt == nil {
        bankSyncSection(account)
      }

      if let account {
        lifecycleSection(account)
      }
    }
    .disabled(isSaving)
    .bowSkyList(mood: .dawn, height: 420)
    .accountLogoPresentations(settings: $logoSettings, presentation: $logoPresentation,
                              lookupName: account?.institutionName ?? name.trimmingCharacters(in: .whitespacesAndNewlines),
                              institutionDomain: account?.institutionDomain)
    .onAppear { if initialFields == nil { initialFields = fields } }
    .onChange(of: type) { old, new in
      // Moving between a debt and a balance keeps the number, with its meaning.
      if old.isDebt != new.isDebt {
        amountMinor = new.isDebt ? abs(amountMinor) : (isInCredit ? amountMinor : -amountMinor)
        if !new.isDebt { isInCredit = false }
      }
    }
    .navigationTitle(account == nil ? "Track it yourself" : "Account")
    .task { await loadCurrentState() }
    .navigationBarTitleDisplayMode(.inline)
    .bowEditorSheet(hasChanges: hasChanges)
    .toolbar {
      // Inside Add Account, Back is enough until there's something to discard.
      if !isInFlow || hasChanges {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
      }
    }
    .navigationBarBackButtonHidden(hasChanges)
    // One primary action at the bottom, creating or editing.
    .safeAreaInset(edge: .bottom) {
      BowBottomAction(account == nil ? "Create account" : "Save changes",
                      isEnabled: canSave && !isSaving && !logoPresentation.isImporting) {
        Task { await save() }
      }
    }
    .bowErrorAlert("Couldn’t save account", message: $errorMessage)
    .sheet(isPresented: $showingBankLinkPicker) {
      if let account {
        SimpleFINLinkPickerScreen(account: account)
      }
    }
    .confirmationDialog("Unlink this bank account?", isPresented: $showingStopBankSync) {
      Button("Unlink", role: .destructive) { unlinkBank() }
    } message: {
      Text("The Bow account and its existing transactions stay in place. You can link it again later.")
    }
    .confirmationDialog(closeTitle, isPresented: $showingClose, titleVisibility: .visible) {
      if currentBalanceMinor == 0 {
        Button("Close Account", role: .destructive) { close(recordingAdjustment: false) }
      } else {
        Button("Record Adjustment and Close", role: .destructive) { close(recordingAdjustment: true) }
      }
    } message: {
      Text(closeMessage)
    }
    .confirmationDialog("Delete this account?", isPresented: $showingDelete, titleVisibility: .visible) {
      Button("Delete Account", role: .destructive) { deleteAccount() }
    } message: {
      Text("It has no transactions yet, so nothing else changes. This can’t be undone.")
    }
  }

  private var footerText: String {
    let balanceLine: String
    if account == nil {
      balanceLine = type.isDebt
        ? "Enter what you owe as of the start of that day. Transactions from that day on change it."
        : "Enter the balance at the start of that day. Transactions from that day on change it."
    } else {
      balanceLine = "Changing the balance records a dated adjustment. Changing the starting balance date keeps today’s balance; anything earlier becomes history."
    }
    return type.explanation + " " + balanceLine
  }

  private var closeTitle: String {
    currentBalanceMinor == 0 ? "Close this account?" : "Close with a balance?"
  }

  private var closeMessage: String {
    let name = account?.name ?? "This account"
    guard currentBalanceMinor != 0 else {
      return "\(name) leaves Accounts, Budget and pickers. Its transactions stay, and you can reopen it here."
    }
    let balance = BudgetMoney.formatted(currentBalanceMinor, currencyCode: currencyCode)
    let budgetEffect = type.kind == .cash
      ? " Ready to Assign changes by the same amount."
      : ""
    return "\(name) still has \(balance). To move it somewhere, cancel and record a transfer. Otherwise Bow records an adjustment to zero, then closes it.\(budgetEffect)"
  }

  @ViewBuilder
  private func bankSyncSection(_ account: BudgetAccount) -> some View {
    Section {
      if let link = simpleFINLinks.first(where: { $0.localAccountID == account.id }) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Linked to \(link.name)")
              .foregroundStyle(Bow.ink)
            Text("Synced with SimpleFIN")
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
          }
        } icon: {
          Image(systemName: "link")
        }
        .labelStyle(.bowTile)
        .accessibilityElement(children: .combine)
        Button("Relink bank account") {
          showingBankLinkPicker = true
        }
        Button("Unlink bank account", role: .destructive) {
          showingStopBankSync = true
        }
      } else {
        Text("This account is not connected to a bank.")
          .font(.bowBody)
          .foregroundStyle(Bow.inkSoft)
        Button("Link a bank account", systemImage: "link") {
          showingBankLinkPicker = true
        }
      }
    } header: {
      Text("Bank sync")
    } footer: {
      Text("Changing or stopping sync keeps transactions already in Bow.")
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }

  @ViewBuilder
  private func lifecycleSection(_ account: BudgetAccount) -> some View {
    Section {
      if account.closedAt == nil {
        Button("Close account", systemImage: "archivebox") { showingClose = true }
          .disabled(hasChanges || !loadedCurrentBalance)
      } else {
        Button("Reopen account", systemImage: "arrow.uturn.backward") { reopen() }
      }
      if !hasActivity {
        Button("Delete account", systemImage: "trash", role: .destructive) { showingDelete = true }
          .foregroundStyle(Bow.overInk)
      }
    } footer: {
      Text(account.closedAt == nil
        ? "Close an account you no longer use. Its history stays in Bow."
        : "Closed \(account.closedAt?.formatted(date: .abbreviated, time: .omitted) ?? ""). Reopening puts it back in Accounts and pickers.")
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }

  /// An existing account's field shows today's balance; closing needs it and the card payment money.
  private func loadCurrentState() async {
    if initialFields == nil { initialFields = fields }
    guard let account, !loadedCurrentBalance else { return }
    hasActivity = (try? BudgetCommands.accountHasActivity(account, in: modelContext)) ?? true
    let wasUnchanged = !hasChanges
    let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
    if let report = try? await repository.accountReport(at: Date(), currencyCode: currencyCode) {
      currentBalanceMinor = report.balances[account.id] ?? account.openingBalanceMinor
      if wasUnchanged {
        amountMinor = type.isDebt ? abs(currentBalanceMinor) : currentBalanceMinor
        isInCredit = type.isDebt && currentBalanceMinor > 0
        initialFields = fields
      }
    }
    if account.kind == .credit, let snapshot = try? await repository.snapshot(month: Date()) {
      reservedMinor = max(0, snapshot.paymentAvailable[account.id, default: 0])
    }
    loadedCurrentBalance = true
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let saved: BudgetAccount
      if let account {
        let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
        await repository.invalidate()
        let report = try await repository.accountReport(at: Date(), currencyCode: currencyCode)
        guard let existingBalance = report.balances[account.id] else {
          throw BudgetCommandError.invalidTransfer
        }
        if type != account.accountType {
          try BudgetCommands.changeAccountType(account, to: type, in: modelContext)
        }
        try BudgetCommands.updateAccount(
          account, name: name, type: type, note: note,
          currentBalanceMinor: signedBalance, existingBalanceMinor: existingBalance,
          logoSettings: logoSettings, startDate: startDate,
          in: modelContext
        )
        saved = account
      } else {
        saved = try BudgetCommands.addAccount(
          name: name,
          kind: type.kind,
          currencyCode: currencyCode,
          openingBalanceMinor: signedBalance,
          type: type,
          note: note,
          logoSettings: logoSettings,
          startDate: startDate,
          in: modelContext
        )
      }
      toasts?.show(.saved("\(account == nil ? "Created" : "Saved") · \(saved.name)"))
      onSaved?(saved)
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }

  private func close(recordingAdjustment: Bool) {
    guard let account else { return }
    do {
      if recordingAdjustment {
        try BudgetCommands.updateAccount(
          account, name: account.name, type: account.accountType, note: account.note,
          currentBalanceMinor: 0, existingBalanceMinor: currentBalanceMinor, in: modelContext
        )
      }
      try BudgetCommands.closeAccount(account, balanceMinor: 0, reservedMinor: reservedMinor, in: modelContext)
      toasts?.show(.saved("Closed · \(account.name)"))
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }

  private func reopen() {
    guard let account else { return }
    do {
      try BudgetCommands.reopenAccount(account, in: modelContext)
      toasts?.show(.saved("Reopened · \(account.name)"))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func deleteAccount() {
    guard let account else { return }
    let name = account.name
    do {
      try BudgetCommands.deleteUnusedAccount(account, in: modelContext)
      toasts?.show(.deleted("Deleted · \(name)"))
      onDeleted?()
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }

  private func unlinkBank() {
    guard let account,
          let link = simpleFINLinks.first(where: { $0.localAccountID == account.id })
    else { return }
    link.localAccountID = nil
    do { try modelContext.save() }
    catch {
      link.localAccountID = account.id
      errorMessage = error.localizedDescription
    }
  }
}

private struct AccountEditorFields: Equatable {
  var name: String
  var type: BudgetAccountType
  var balance: Int64
  var startDay: Date
  var note: String
  var logoSettings: AccountLogoSettings
}
