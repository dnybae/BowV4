import SwiftUI
import SwiftData

struct TransactionEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var schedules: [BudgetSchedule]
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
  @State private var merchantDomain: String?
  @State private var notes: String
  @State private var date: Date
  @State private var isScheduled = false
  @State private var recurrence: ScheduleFrequency = .once
  @State private var errorMessage: String?
  @State private var showingDeleteConfirmation = false
  @State private var possibleImportedMatchIDs: [UUID] = []
  @State private var autoAssignedEnvelopeID: UUID?
  @State private var linkScheduledBill = true
  @State private var showingPayeeSelection = false

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
    _kind = State(initialValue: transaction?.kind ?? scheduledDraft?.kind ?? .expense)
    _accountID = State(initialValue: transaction?.accountID ?? scheduledDraft?.accountID
      ?? accounts.first(where: { $0.kind == .cash })?.id
      ?? accounts.first(where: { $0.kind == .credit })?.id
      ?? accounts.first?.id)
    _destinationID = State(initialValue: transaction?.transferAccountID ?? scheduledDraft?.transferAccountID)
    _envelopeID = State(initialValue: transaction?.envelopeID ?? scheduledDraft?.envelopeID)
    _amount = State(initialValue: transaction.map { BudgetMoney.editable($0.amountMinor) } ?? scheduledDraft.map { BudgetMoney.editable($0.amountMinor) } ?? "")
    _payee = State(initialValue: transaction?.payee ?? scheduledDraft?.payee ?? "")
    _merchantDomain = State(initialValue: transaction?.merchantDomain)
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

  private var categoryNoneTitle: String {
    if kind == .inflow {
      return selectedAccount?.kind == .cash ? "Ready to Assign" : "No Category"
    }
    return "Needs Categorization"
  }

  private var matchingSchedule: BudgetSchedule? {
    guard let transaction, transaction.needsApproval, transaction.scheduleID == nil,
          kind == .expense, let accountID, let minor = BudgetMoney.parseMinor(amount) else { return nil }
    let matches = schedules.filter { schedule in
      schedule.accountID == accountID && schedule.amountMinor == minor
        && schedule.payee.localizedCaseInsensitiveCompare(payee) == .orderedSame
        && ScheduleRecurrence().occurs(
          starting: schedule.startDate, frequency: schedule.frequency, on: date
        )
        && (try? BudgetTransactionLookup.scheduled(
          scheduleID: schedule.id, on: date, excluding: transaction.id, in: modelContext
        )) == nil
    }
    return matches.count == 1 ? matches.first : nil
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
        if let matchingSchedule {
          ScheduledMatchSection(
            payee: matchingSchedule.payee, date: date,
            isLinked: $linkScheduledBill
          )
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
          DatePicker(isScheduled ? "First due" : "Date", selection: $date,
                     in: Date.distantPast...Date.distantFuture, displayedComponents: .date)
        }
        Section("Details") {
          AccountSelectionField(title: "Account", selection: $accountID, accounts: accounts)
          if kind == .transfer {
            AccountSelectionField(
              title: "To Account", selection: $destinationID,
              accounts: accounts, excludingID: accountID
            )
          } else {
            Button {
              showingPayeeSelection = true
            } label: {
              HStack(spacing: 12) {
                Text(kind == .expense ? "Payee" : "Source").foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(payee.isEmpty ? "Choose a payee" : payee)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
              .contentShape(Rectangle())
            }
            .accessibilityLabel("\(kind == .expense ? "Payee" : "Source"), \(payee.isEmpty ? "Choose a payee" : payee)")
          }
          if kind != .transfer || needsEnvelopeForTransfer {
            CategorySelectionField(
              title: "Category", selection: $envelopeID,
              envelopes: envelopes, noneTitle: categoryNoneTitle
            )
            if kind == .expense && envelopeID == nil {
              Text("Choose an envelope before saving this expense.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          if kind != .transfer && (selectedAccount?.kind == .asset || selectedAccount?.kind == .liability) {
            Text("Categories on tracking accounts are for reference and don't change your budget.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(2...4)
        }
        if transaction == nil && scheduledDraft == nil {
          Section("Schedule") {
            Toggle("Schedule for later", isOn: $isScheduled)
            if isScheduled {
              Picker("Repeats", selection: $recurrence) {
                ForEach(ScheduleFrequency.allCases) { frequency in
                  Text(frequency.title).tag(frequency)
                }
              }
              .pickerStyle(.menu)
              Text("Scheduled entries appear on the calendar and affect balances only when recorded.")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
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
      .navigationTitle(transaction == nil ? (scheduledDraft == nil ? "Add Transaction" : "Record Scheduled Transaction") : "Edit Transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(accountID == nil || amount.isEmpty
              || (kind == .expense && envelopeID == nil))
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
        Text("An imported transaction may already represent this payment. Updating it keeps one ledger entry and uses the details you entered.")
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
      .sheet(isPresented: $showingPayeeSelection) {
        PayeeSelectionSheet(selectedName: payee) { selected in
          payee = selected.name
          merchantDomain = selected.merchantDomain
          showingPayeeSelection = false
        }
      }
    }
  }

  private func applyPayeeRule() {
    let nextEnvelopeID: UUID?
    if kind == .expense {
      let matcher = PayeeRuleMatcher()
      let rules = PayeeDirectory.ruleItems(
        payees: payees,
        validEnvelopeIDs: Set(envelopes.filter { !$0.isHidden && $0.paymentAccountID == nil }.map(\.id))
      )
      nextEnvelopeID = matcher.envelopeID(for: payee, rules: rules)
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
    if !isScheduled && Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date()) {
      errorMessage = "Turn on Schedule for later to plan a future transaction."
      return
    }
    if isScheduled && Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()) {
      errorMessage = "Choose today or a future date for a scheduled transaction."
      return
    }
    let chosenEnvelopeID = kind == .transfer && !needsEnvelopeForTransfer
      ? nil : envelopeID
    let linkedScheduleID = scheduledDraft?.scheduleID
      ?? (linkScheduledBill ? matchingSchedule?.id : nil)
    let linkedScheduledFor = scheduledDraft?.scheduledFor
      ?? (linkScheduledBill && matchingSchedule != nil ? date : nil)
    if isScheduled && transaction == nil && scheduledDraft == nil {
      do {
        try BudgetCommands.addSchedule(
          kind: kind, account: account, destination: destination,
          envelopeID: chosenEnvelopeID, amountMinor: minor, startDate: date,
          frequency: recurrence, payee: payee, notes: notes, in: modelContext
        )
        dismiss()
      } catch { errorMessage = error.localizedDescription }
      return
    }
    if transaction == nil && importedID == nil && !allowSeparate && kind != .transfer {
      let signedAmount = kind == .inflow ? minor : -minor
      possibleImportedMatchIDs = ((try? BudgetTransactionLookup.near(
        accountID: account.id, date: date, days: scheduledDraft == nil ? 10 : 3,
        in: modelContext
      )) ?? []).filter {
        ($0.sourceRaw == "simplefin" || $0.sourceRaw == "bankFile")
          && $0.accountID == account.id
          && $0.amountMinor == signedAmount
          && $0.scheduleID == nil
          && abs($0.date.timeIntervalSince(date)) <= (scheduledDraft == nil ? 10 : 3) * 86_400
          && (scheduledDraft == nil || $0.payee.localizedCaseInsensitiveCompare(payee) == .orderedSame)
      }.map(\.id)
      if !possibleImportedMatchIDs.isEmpty { return }
    }
    do {
      if let transaction = transaction ?? importedID.flatMap({ try? BudgetTransactionLookup.byID($0, in: modelContext) }) {
        try BudgetCommands.updateTransaction(
          transaction,
          kind: kind,
          account: account,
          destination: destination,
          envelopeID: chosenEnvelopeID,
          amountMinor: minor,
          date: date,
          payee: payee,
          merchantDomain: merchantDomain,
          notes: notes,
          scheduleID: linkedScheduleID,
          scheduledFor: linkedScheduledFor,
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
          merchantDomain: merchantDomain,
          notes: notes,
          scheduleID: linkedScheduleID,
          scheduledFor: linkedScheduledFor,
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
  var transferAccountID: UUID? = nil
  var envelopeID: UUID?
  var kind: BudgetTransactionKind = .expense
  var amountMinor: Int64
  var payee: String
  var notes: String
  var date: Date
}

private struct ScheduledMatchSection: View {
  var payee: String
  var date: Date
  @Binding var isLinked: Bool

  var body: some View {
    Section {
      Toggle("Link to \(payee) on \(date.formatted(date: .abbreviated, time: .omitted))", isOn: $isLinked)
    } header: {
      Text("Scheduled Bill")
    } footer: {
      Text("Linking marks this bill recorded without creating another transaction.")
    }
  }
}
