import SwiftUI
import SwiftData

struct AccountEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var currencyCode: String
  var account: BudgetAccount?
  @State private var name: String
  @State private var kind: BudgetAccountKind
  @State private var openingBalance: String
  @State private var errorMessage: String?

  init(currencyCode: String, account: BudgetAccount? = nil) {
    self.currencyCode = currencyCode
    self.account = account
    _name = State(initialValue: account?.name ?? "")
    _kind = State(initialValue: account?.kind ?? .cash)
    _openingBalance = State(initialValue: account.map { BudgetMoney.editableSigned($0.openingBalanceMinor) } ?? "")
  }

  private var parsedOpeningBalance: Int64? {
    BudgetMoney.parseMinor(openingBalance.isEmpty ? "0" : openingBalance)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          TextField("Name", text: $name)
          if account == nil {
            Picker("Type", selection: $kind) {
              ForEach(BudgetAccountKind.allCases) { kind in
                Label(kind.title, systemImage: kind.systemImage).tag(kind)
              }
            }
          } else {
            LabeledContent("Type", value: kind.title)
          }
        }
        Section {
          TextField("Opening Balance", text: $openingBalance)
            .keyboardType(.numbersAndPunctuation)
        } header: {
          Text("Balance")
        } footer: {
          Text(account == nil
            ? "Enter a negative balance for money owed. Opening cash becomes Ready to Assign; credit and tracking balances do not."
            : "Changing the opening balance updates this account, net worth, and Ready to Assign for cash accounts. It clears the last reconciliation.")
        }
      }
      .navigationTitle(account == nil ? "Add Account" : "Edit Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(account == nil ? "Add" : "Save") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || parsedOpeningBalance == nil)
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
  }

  private func save() {
    guard let minor = parsedOpeningBalance
    else {
      errorMessage = "Enter a valid balance with no more than two decimal places."
      return
    }
    do {
      if let account {
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.openingBalanceMinor != minor {
          account.openingBalanceMinor = minor
          account.lastReconciledAt = nil
          account.lastReconciledBalanceMinor = nil
        }
        try modelContext.save()
      } else {
        try BudgetCommands.addAccount(
          name: name,
          kind: kind,
          currencyCode: currencyCode,
          openingBalanceMinor: minor,
          in: modelContext
        )
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
