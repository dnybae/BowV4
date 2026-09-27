import SwiftUI
import SwiftData

struct AccountEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var currencyCode: String
  @State private var name = ""
  @State private var kind: BudgetAccountKind = .cash
  @State private var openingBalance = ""
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          TextField("Name", text: $name)
          Picker("Type", selection: $kind) {
            ForEach(BudgetAccountKind.allCases) { kind in
              Label(kind.title, systemImage: kind.systemImage).tag(kind)
            }
          }
        }
        Section {
          TextField("Opening Balance", text: $openingBalance)
            .keyboardType(.numbersAndPunctuation)
        } header: {
          Text("Balance")
        } footer: {
          Text("Enter a negative balance for money owed. Opening cash becomes Ready to Assign; credit and tracking balances do not.")
        }
      }
      .navigationTitle("Add Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("Couldn’t Add Account", isPresented: Binding(
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
    guard let minor = BudgetMoney.parseMinor(openingBalance.isEmpty ? "0" : openingBalance)
    else {
      errorMessage = "Enter a valid balance with no more than two decimal places."
      return
    }
    do {
      try BudgetCommands.addAccount(
        name: name,
        kind: kind,
        currencyCode: currencyCode,
        openingBalanceMinor: minor,
        in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
