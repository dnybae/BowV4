import SwiftUI
import SwiftData

struct AccountEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var currencyCode: String
  var account: BudgetAccount?
  var onSaved: ((BudgetAccount) -> Void)?
  @State private var name: String
  @State private var type: BudgetAccountType
  @State private var openingBalance: String
  @State private var note: String
  @State private var errorMessage: String?

  init(currencyCode: String, account: BudgetAccount? = nil,
       suggestedName: String = "", suggestedBalanceMinor: Int64? = nil,
       onSaved: ((BudgetAccount) -> Void)? = nil) {
    self.currencyCode = currencyCode
    self.account = account
    self.onSaved = onSaved
    _name = State(initialValue: account?.name ?? suggestedName)
    _type = State(initialValue: account?.accountType ?? .checking)
    _openingBalance = State(initialValue: account.map { BudgetMoney.editableSigned($0.openingBalanceMinor) }
      ?? suggestedBalanceMinor.map(BudgetMoney.editableSigned) ?? "")
    _note = State(initialValue: account?.note ?? "")
  }

  private var parsedOpeningBalance: Int64? {
    BudgetMoney.parseMinor(openingBalance.isEmpty ? "0" : openingBalance)
  }

  private var availableTypes: [BudgetAccountType] {
    BudgetAccountType.allCases.filter { account == nil || $0.kind == account?.kind }
  }

  var body: some View {
    Form {
      Section {
        TextField("Account Name", text: $name)
          .submitLabel(.done)
        if availableTypes.count > 1 {
          Picker("Type", selection: $type) {
            ForEach(availableTypes) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.menu)
        } else {
          LabeledContent("Type", value: type.title)
        }
      } header: {
        Text("Account")
      } footer: {
        Text(type.explanation)
      }

      Section {
        TextField(account == nil ? "Starting Balance" : "Opening Balance", text: $openingBalance)
          .keyboardType(.numbersAndPunctuation)
          .accessibilityHint("Enter zero or a signed amount in \(currencyCode).")
      } header: {
        Text("Balance")
      } footer: {
        Text(account == nil
          ? "Enter the balance this account should start with. New transactions will change it."
          : "This is the balance before recorded transactions. Changing it updates net worth and clears the last reconciliation.")
      }

      Section("Note") {
        TextField("Optional note", text: $note, axis: .vertical)
          .lineLimit(2...4)
      }
    }
    .navigationTitle(account == nil ? "Private Account" : "Edit Account")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if account != nil {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if account == nil {
        Button(action: save) {
          Text("Create Account")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
      }
    }
    .alert("Couldn’t Save Account", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedOpeningBalance != nil
  }

  private func save() {
    guard let minor = parsedOpeningBalance else {
      errorMessage = "Enter a valid balance with no more than two decimal places."
      return
    }
    do {
      let saved: BudgetAccount
      if let account {
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.typeRaw = type.rawValue
        account.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.openingBalanceMinor != minor {
          account.openingBalanceMinor = minor
          account.lastReconciledAt = nil
          account.lastReconciledBalanceMinor = nil
        }
        try modelContext.save()
        saved = account
      } else {
        saved = try BudgetCommands.addAccount(
          name: name,
          kind: type.kind,
          currencyCode: currencyCode,
          openingBalanceMinor: minor,
          type: type,
          note: note,
          in: modelContext
        )
      }
      onSaved?(saved)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
