import SwiftUI
import SwiftData

struct TransactionEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var transaction: BudgetTransaction?
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  @State private var kind: BudgetTransactionKind
  @State private var accountID: UUID?
  @State private var destinationID: UUID?
  @State private var envelopeID: UUID?
  @State private var amount: String
  @State private var payee: String
  @State private var notes: String
  @State private var date: Date
  @State private var errorMessage: String?
  @State private var showingDeleteConfirmation = false

  init(
    transaction: BudgetTransaction?,
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    currencyCode: String
  ) {
    self.transaction = transaction
    self.accounts = accounts
    self.envelopes = envelopes
    self.currencyCode = currencyCode
    _kind = State(initialValue: transaction?.kind ?? .expense)
    _accountID = State(initialValue: transaction?.accountID ?? accounts.first?.id)
    _destinationID = State(initialValue: transaction?.transferAccountID)
    _envelopeID = State(initialValue: transaction?.envelopeID)
    _amount = State(initialValue: transaction.map { BudgetMoney.editable($0.amountMinor) } ?? "")
    _payee = State(initialValue: transaction?.payee ?? "")
    _notes = State(initialValue: transaction?.notes ?? "")
    _date = State(initialValue: transaction?.date ?? Date())
  }

  private var selectedAccount: BudgetAccount? {
    accounts.first { $0.id == accountID }
  }

  private var needsEnvelopeForTransfer: Bool {
    guard kind == .transfer,
          selectedAccount?.kind == .cash,
          let destination = accounts.first(where: { $0.id == destinationID })
    else { return false }
    return destination.kind == .asset || destination.kind == .liability
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Type", selection: $kind) {
            ForEach(BudgetTransactionKind.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)
          TextField("Amount", text: $amount)
            .keyboardType(.decimalPad)
          DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
        }
        Section("Details") {
          Picker("Account", selection: $accountID) {
            ForEach(accounts) { account in
              Text(account.name).tag(Optional(account.id))
            }
          }
          if kind == .transfer {
            Picker("To Account", selection: $destinationID) {
              Text("Choose an account").tag(nil as UUID?)
              ForEach(accounts.filter { $0.id != accountID }) { account in
                Text(account.name).tag(Optional(account.id))
              }
            }
          } else {
            TextField(kind == .expense ? "Payee" : "Source", text: $payee)
              .textInputAutocapitalization(.words)
          }
          if (kind != .transfer && selectedAccount?.kind != .asset
              && selectedAccount?.kind != .liability)
              || needsEnvelopeForTransfer {
            Picker("Envelope", selection: $envelopeID) {
              Text("Needs Categorization").tag(nil as UUID?)
              ForEach(envelopes) { envelope in
                Text(envelope.name).tag(Optional(envelope.id))
              }
            }
          }
          TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(2...4)
        }

        if accounts.isEmpty {
          Section {
            ContentUnavailableView(
              "Add an account first",
              systemImage: "banknote.fill",
              description: Text("Transactions need an account.")
            )
          }
        }

        if transaction != nil {
          Section {
            Button("Delete Transaction", role: .destructive) {
              showingDeleteConfirmation = true
            }
          }
        }
      }
      .navigationTitle(transaction == nil ? "Add Transaction" : "Edit Transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(accountID == nil || amount.isEmpty)
        }
      }
      .confirmationDialog(
        "Delete this transaction?",
        isPresented: $showingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete Transaction", role: .destructive) { delete() }
      } message: {
        Text("Its effect on your accounts and envelopes will be removed.")
      }
      .alert("Couldn’t Save Transaction", isPresented: Binding(
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
    guard let account = selectedAccount,
          let minor = BudgetMoney.parseMinor(amount) else {
      errorMessage = "Choose an account and enter a valid amount."
      return
    }
    let destination = accounts.first { $0.id == destinationID }
    let chosenEnvelopeID = kind == .transfer && !needsEnvelopeForTransfer
      ? nil : envelopeID
    do {
      if let transaction {
        try BudgetCommands.updateTransaction(
          transaction,
          kind: kind,
          account: account,
          destination: destination,
          envelopeID: chosenEnvelopeID,
          amountMinor: minor,
          date: date,
          payee: payee,
          notes: notes,
          in: modelContext
        )
      } else {
        try BudgetCommands.addTransaction(
          kind: kind,
          account: account,
          destination: destination,
          envelopeID: chosenEnvelopeID,
          amountMinor: minor,
          date: date,
          payee: payee,
          notes: notes,
          in: modelContext
        )
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete() {
    guard let transaction else { return }
    do {
      try BudgetCommands.deleteTransaction(transaction, in: modelContext)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
