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
  var onSaved: ((BudgetAccount) -> Void)?
  @State private var name: String
  @State private var type: BudgetAccountType
  @State private var openingBalanceMinor: Int64
  @State private var note: String
  @State private var errorMessage: String?
  @State private var loadedCurrentBalance = false
  @State private var showingBankLinkPicker = false
  @State private var showingStopBankSync = false
  @State private var initialFields: AccountEditorFields?
  @State private var isSaving = false
  @State private var logoSettings: AccountLogoSettings
  @State private var isImportingLogo = false
  @Environment(\.bowToasts) private var toasts

  init(currencyCode: String, account: BudgetAccount? = nil,
       suggestedName: String = "", suggestedBalanceMinor: Int64? = nil,
       onSaved: ((BudgetAccount) -> Void)? = nil) {
    self.currencyCode = currencyCode
    self.account = account
    self.onSaved = onSaved
    _name = State(initialValue: account?.name ?? suggestedName)
    _type = State(initialValue: account?.accountType ?? .checking)
    _openingBalanceMinor = State(initialValue: account?.openingBalanceMinor ?? suggestedBalanceMinor ?? 0)
    _note = State(initialValue: account?.note ?? "")
    _logoSettings = State(initialValue: account?.logoSettings ?? AccountLogoSettings())
  }

  private var fields: AccountEditorFields {
    AccountEditorFields(name: name, type: type, balance: openingBalanceMinor, note: note, logoSettings: logoSettings)
  }

  private var hasChanges: Bool { initialFields.map { fields != $0 } ?? false }

  private var parsedOpeningBalance: Int64? {
    openingBalanceMinor
  }

  private var availableTypes: [BudgetAccountType] {
    BudgetAccountType.allCases.filter { account == nil || $0.kind == account?.kind }
  }

  var body: some View {
    Form {
      Section {
        BowNameHeader(placeholder: "Account name", name: $name) {
          AccountLogoView(appearance: logoSettings.appearance(
            institutionName: account?.institutionName, institutionDomain: account?.institutionDomain),
            systemImage: type.kind.systemImage, size: 64, style: .glossy)
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      Section {
        if availableTypes.count > 1 {
          Picker(selection: $type) {
            ForEach(availableTypes) { option in
              Text(option.title).tag(option)
            }
          } label: {
            Label("Type", systemImage: type.kind.systemImage).labelStyle(.bowTile)
          }
          .pickerStyle(.menu)
        } else {
          BowTileValueRow("Type", systemImage: type.kind.systemImage, value: type.title)
        }
        CurrencyAmountField(account == nil ? "Starting balance" : "Balance",
                            minor: $openingBalanceMinor, currencyCode: currencyCode, allowsNegative: true,
                            systemImage: "dollarsign")
        if type.kind == .liability && (parsedOpeningBalance ?? 0) > 0 {
          Text("Enter money owed as a negative balance.")
            .font(.bowFootnote)
            .foregroundStyle(Bow.overInk)
        }
        BowNotesRow(notes: $note)
      } footer: {
        Group {
          Text(type.explanation + " " + (account == nil
            ? "Enter the balance this account should start with. New transactions will change it."
            : "Changing the current balance records a dated adjustment. Earlier net worth history stays intact."))
        }
        .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)

      AccountLogoControls(settings: $logoSettings, isImporting: $isImportingLogo,
                          accountName: name, institutionName: account?.institutionName,
                          institutionDomain: account?.institutionDomain)

      if let account, !isDemoMode, !simpleFINConnections.isEmpty {
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
    }
    .disabled(isSaving)
    .bowSkyList(mood: .dawn, height: 420)
    .onAppear { if initialFields == nil { initialFields = fields } }
    .navigationTitle(account == nil ? "Private account" : "Account")
    .task {
      if initialFields == nil { initialFields = fields }
      guard let account, !loadedCurrentBalance else { return }
      let displayedBeforeLoad = openingBalanceMinor
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      if let report = try? await repository.accountReport(at: Date(), currencyCode: currencyCode) {
        if openingBalanceMinor == displayedBeforeLoad {
          openingBalanceMinor = report.balances[account.id] ?? account.openingBalanceMinor
          initialFields?.balance = openingBalanceMinor
        }
      }
      loadedCurrentBalance = true
    }
    .navigationBarTitleDisplayMode(.inline)
    .bowEditorSheet(hasChanges: hasChanges)
    .toolbar {
      BowCancelButton(hasChanges: hasChanges) { dismiss() }
    }
    .navigationBarBackButtonHidden(hasChanges)
    // One primary action at the bottom, creating or editing.
    .safeAreaInset(edge: .bottom) {
      BowBottomAction(account == nil ? "Create account" : "Save changes", isEnabled: canSave && !isSaving && !isImportingLogo) {
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
      Button("Unlink", role: .destructive) {
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
    } message: {
      Text("The Bow account and its existing transactions stay in place. You can link it again later.")
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && parsedOpeningBalance != nil
      && (type.kind != .liability || (parsedOpeningBalance ?? 0) <= 0)
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    guard let minor = parsedOpeningBalance else {
      errorMessage = "Enter a valid balance with no more than two decimal places."
      return
    }
    do {
      let saved: BudgetAccount
      if let account {
        let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
        await repository.invalidate()
        let report = try await repository.accountReport(at: Date(), currencyCode: currencyCode)
        guard let existingBalance = report.balances[account.id] else {
          throw BudgetCommandError.invalidTransfer
        }
        try BudgetCommands.updateAccount(
          account, name: name, type: type, note: note,
          currentBalanceMinor: minor, existingBalanceMinor: existingBalance,
          logoSettings: logoSettings,
          in: modelContext
        )
        saved = account
      } else {
        saved = try BudgetCommands.addAccount(
          name: name,
          kind: type.kind,
          currencyCode: currencyCode,
          openingBalanceMinor: minor,
          type: type,
          note: note,
          logoSettings: logoSettings,
          in: modelContext
        )
      }
      toasts?.show(.saved("\(account == nil ? "Created" : "Saved") · \(saved.name)"))
      onSaved?(saved)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct AccountEditorFields: Equatable {
  var name: String
  var type: BudgetAccountType
  var balance: Int64
  var note: String
  var logoSettings: AccountLogoSettings
}
