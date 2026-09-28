import SwiftUI
import SwiftData

struct TransactionEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var existingTransactions: [BudgetTransaction]
  var transaction: BudgetTransaction?
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var payees: [BudgetPayee]
  var currencyCode: String
  var scheduledDraft: ScheduledTransactionDraft?
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
  @State private var possibleImportedMatchIDs: [UUID] = []
  @State private var autoAssignedEnvelopeID: UUID?

  init(
    transaction: BudgetTransaction?,
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    payees: [BudgetPayee],
    currencyCode: String,
    scheduledDraft: ScheduledTransactionDraft? = nil
  ) {
    self.transaction = transaction
    self.accounts = accounts
    self.envelopes = envelopes
    self.payees = payees
    self.currencyCode = currencyCode
    self.scheduledDraft = scheduledDraft
    _kind = State(initialValue: transaction?.kind ?? .expense)
    _accountID = State(initialValue: transaction?.accountID ?? scheduledDraft?.accountID ?? accounts.first?.id)
    _destinationID = State(initialValue: transaction?.transferAccountID)
    _envelopeID = State(initialValue: transaction?.envelopeID ?? scheduledDraft?.envelopeID)
    _amount = State(initialValue: transaction.map { BudgetMoney.editable($0.amountMinor) } ?? scheduledDraft.map { BudgetMoney.editable($0.amountMinor) } ?? "")
    _payee = State(initialValue: transaction?.payee ?? scheduledDraft?.payee ?? "")
    _notes = State(initialValue: transaction?.notes ?? scheduledDraft?.notes ?? "")
    _date = State(initialValue: transaction?.date ?? scheduledDraft?.date ?? Date())
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
        if transaction?.needsApproval == true {
          Section {
            Text("Review this imported transaction. Saving it marks it approved.")
              .foregroundStyle(.secondary)
          }
        }
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
      .navigationTitle(transaction == nil ? (scheduledDraft == nil ? "Add Transaction" : "Record Payment") : "Edit Transaction")
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
      .confirmationDialog(
        "Possible imported match",
        isPresented: Binding(
          get: { !possibleImportedMatchIDs.isEmpty },
          set: { if !$0 { possibleImportedMatchIDs = [] } }
        ),
        titleVisibility: .visible
      ) {
        if possibleImportedMatchIDs.count == 1,
           let id = possibleImportedMatchIDs.first {
          Button("Update Imported Transaction") {
            possibleImportedMatchIDs = []
            save(matching: id)
          }
        }
        Button("Add Separate Transaction") {
          possibleImportedMatchIDs = []
          save(allowSeparate: true)
        }
        Button("Cancel", role: .cancel) { possibleImportedMatchIDs = [] }
      } message: {
        Text("A SimpleFIN transaction has the same amount in this account within ten days. Updating it keeps one ledger entry and uses the details you entered.")
      }
      .alert("Couldn’t Save Transaction", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .onChange(of: payee) { _, _ in applyPayeeRule() }
      .onChange(of: kind) { _, _ in applyPayeeRule() }
      .onChange(of: accountID) { _, newAccountID in
        if destinationID == newAccountID { destinationID = nil }
      }
    }
  }

  private func applyPayeeRule() {
    let nextEnvelopeID: UUID?
    if kind == .expense {
      let rules = payees.compactMap { rule -> PayeeRuleItem? in
        guard let id = rule.defaultEnvelopeID,
              envelopes.contains(where: { $0.id == id }) else { return nil }
        return PayeeRuleItem(matchText: rule.exactMatchText, envelopeID: id)
      }
      nextEnvelopeID = PayeeRuleMatcher().envelopeID(for: payee, rules: rules)
    } else {
      nextEnvelopeID = nil
    }
    if envelopeID == nil || envelopeID == autoAssignedEnvelopeID {
      envelopeID = nextEnvelopeID
      autoAssignedEnvelopeID = nextEnvelopeID
    }
  }

  private func save(allowSeparate: Bool = false, matching importedID: UUID? = nil) {
    guard let account = selectedAccount,
          let minor = BudgetMoney.parseMinor(amount) else {
      errorMessage = "Choose an account and enter a valid amount."
      return
    }
    let destination = accounts.first { $0.id == destinationID }
    let chosenEnvelopeID = kind == .transfer && !needsEnvelopeForTransfer
      ? nil : envelopeID
    if transaction == nil && importedID == nil && !allowSeparate && scheduledDraft == nil
        && kind != .transfer {
      let signedAmount = kind == .inflow ? minor : -minor
      possibleImportedMatchIDs = existingTransactions.filter {
        $0.sourceRaw == "simplefin" && $0.accountID == account.id
          && $0.amountMinor == signedAmount
          && abs($0.date.timeIntervalSince(date)) <= 10 * 86_400
      }.map(\.id)
      if !possibleImportedMatchIDs.isEmpty { return }
    }
    do {
      if let transaction = transaction ?? existingTransactions.first(where: { $0.id == importedID }) {
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
          scheduleID: scheduledDraft?.scheduleID,
          scheduledFor: scheduledDraft?.scheduledFor,
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

struct ScheduledTransactionDraft {
  var scheduleID: UUID
  var scheduledFor: Date
  var accountID: UUID?
  var envelopeID: UUID?
  var amountMinor: Int64
  var payee: String
  var notes: String
  var date: Date
}
