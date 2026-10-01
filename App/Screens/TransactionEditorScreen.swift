import SwiftUI
import SwiftData

struct TransactionEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var schedules: [BudgetSchedule]
  /// The bank record behind this transaction, if it was imported.
  @Query private var importRecords: [SimpleFINImportRecord]
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
  @State private var amountMinor: Int64
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
  @State private var autoFilledAccountID: UUID?
  private var defaultAccountID: UUID?
  @State private var linkScheduledBill = true
  @State private var showingPayeeSelection = false
  @State private var showingIgnoreConfirmation = false
  /// Reviewing an imported transaction: fixed when the sheet opens, so it doesn't change on save.
  @State private var isReviewing: Bool

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
    let defaultAccountID = transaction?.accountID ?? scheduledDraft?.accountID
      ?? accounts.first(where: { $0.kind == .cash })?.id
      ?? accounts.first(where: { $0.kind == .credit })?.id
      ?? accounts.first?.id
    self.defaultAccountID = defaultAccountID
    _accountID = State(initialValue: defaultAccountID)
    _destinationID = State(initialValue: transaction?.transferAccountID ?? scheduledDraft?.transferAccountID)
    _envelopeID = State(initialValue: transaction?.envelopeID ?? scheduledDraft?.envelopeID)
    _amountMinor = State(initialValue: transaction.map { abs($0.amountMinor) } ?? scheduledDraft.map { abs($0.amountMinor) } ?? 0)
    _payee = State(initialValue: transaction?.payee ?? scheduledDraft?.payee ?? "")
    _merchantDomain = State(initialValue: transaction?.merchantDomain)
    _notes = State(initialValue: transaction?.notes ?? scheduledDraft?.notes ?? "")
    _date = State(initialValue: transaction?.date ?? scheduledDraft?.date ?? Date())
    _isReviewing = State(initialValue: transaction?.needsImportReview == true)
    let transactionID = transaction?.id
    _importRecords = Query(filter: #Predicate<SimpleFINImportRecord> { $0.transactionID == transactionID })
  }

  /// The posted bank record this review came from; ignoring it removes the transaction.
  private var importRecord: SimpleFINImportRecord? {
    guard transaction != nil else { return nil }
    return importRecords.first { $0.status == .imported && $0.bankState == .posted }
  }

  private var title: String {
    if isReviewing { return "Review transaction" }
    if transaction != nil { return "Edit transaction" }
    return scheduledDraft == nil ? "New transaction" : "Record scheduled bill"
  }

  private var canSave: Bool {
    accountID != nil && amountMinor != 0 && !(kind == .expense && envelopeID == nil)
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

  private var envelopeNoneTitle: String {
    if kind == .inflow {
      return selectedAccount?.kind == .cash ? "Ready to Assign" : "No envelope"
    }
    return "Needs an envelope"
  }

  private var matchingSchedule: BudgetSchedule? {
    guard let transaction, transaction.needsApproval, transaction.scheduleID == nil,
          kind == .expense, let accountID else { return nil }
    let minor = amountMinor
    let matches = schedules.filter { schedule in
      schedule.accountID == accountID && schedule.amountMinor == minor
        && PayeeDirectory.isSamePayee(schedule.payee, payee, payees: payees)
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
        if isReviewing, let transaction {
          Section {
            ReviewContextCard(
              transaction: transaction, record: importRecord,
              accountName: accounts.first { $0.id == transaction.accountID }?.name
            )
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        Section {
          VStack(spacing: Bow.Space.s4) {
            // The bank sets the direction of an imported transaction.
            if !isReviewing {
              Picker("Type", selection: $kind) {
                ForEach(BudgetTransactionKind.allCases) { option in
                  Text(option.title).tag(option)
                }
              }
              .pickerStyle(.segmented)
            }
            CurrencyAmountField("Amount", minor: $amountMinor, currencyCode: currencyCode, style: .editorHero)
          }
          .padding(.bottom, Bow.Space.s2)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        Section {
          if kind == .transfer {
            AccountSelectionField(title: "From account", selection: $accountID, accounts: accounts,
                                  systemImage: "creditcard")
            AccountSelectionField(
              title: "To account", selection: $destinationID,
              accounts: accounts, excludingID: accountID, systemImage: "arrow.right"
            )
          } else {
            Button {
              showingPayeeSelection = true
            } label: {
              HStack(spacing: 12) {
                BowFieldTitle(title: kind == .expense ? "Payee" : "Source", systemImage: "person")
                Spacer(minLength: 12)
                Text(payee.isEmpty ? "Choose a payee" : payee)
                  .foregroundStyle(Bow.inkSoft)
                  .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                  .font(.subheadline)
                  .foregroundStyle(Bow.inkFaint)
              }
              .contentShape(Rectangle())
            }
            .accessibilityLabel("\(kind == .expense ? "Payee" : "Source"), \(payee.isEmpty ? "Choose a payee" : payee)")
          }
          if kind != .transfer || needsEnvelopeForTransfer {
            EnvelopeSelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: envelopeNoneTitle, systemImage: "square.grid.2x2"
            )
          }
          if kind != .transfer {
            AccountSelectionField(title: "Account", selection: $accountID, accounts: accounts,
                                  systemImage: "creditcard")
          }
          NavigationLink {
            TransactionDatePickerScreen(title: isScheduled ? "First due" : "Date", date: $date)
          } label: {
            LabeledContent {
              Text(date.formatted(date: .abbreviated, time: .omitted))
            } label: {
              Label(isScheduled ? "First due" : "Date", systemImage: "calendar")
                .labelStyle(.bowTile)
            }
          }
          BowNotesRow(notes: $notes)
        } footer: {
          if let fieldsFootnote {
            Text(fieldsFootnote)
          }
        }
        .listRowBackground(Bow.card)
        if let matchingSchedule {
          ScheduledMatchSection(
            payee: matchingSchedule.payee, date: date,
            isLinked: $linkScheduledBill
          )
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
                .font(.footnote).foregroundStyle(Bow.inkSoft)
            }
          }
          .listRowBackground(Bow.card)
        }

        if accounts.isEmpty {
          Section {
            ContentUnavailableView(
              "Add an account first",
              systemImage: "banknote.fill",
              description: Text("Transactions need an account.")
            )
          }
          .listRowBackground(Bow.card)
        }

        if isReviewing && importRecord != nil {
          BowDestructiveSection("Ignore bank transaction") {
            showingIgnoreConfirmation = true
          }
        } else if transaction != nil {
          BowDestructiveSection("Delete transaction") {
            showingDeleteConfirmation = true
          }
        }
      }
      .bowSkyList(mood: isReviewing ? .review : .dawn, height: 420)
      .safeAreaInset(edge: .bottom) {
        if isReviewing {
          Button { save() } label: {
            Text(transaction?.needsApproval == true ? "Approve and add to budget" : "Add to budget")
              .frame(maxWidth: .infinity)
          }
          .bowPrimaryButton()
          .disabled(!canSave)
          .padding(.horizontal, Bow.Space.s4)
          .padding(.bottom, Bow.Space.s2)
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
        }
      }
      .confirmationDialog(
        "Delete this transaction?",
        isPresented: $showingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete transaction", role: .destructive) { delete() }
      } message: {
        Text("Its effect on your accounts and envelopes will be removed.")
      }
      .confirmationDialog(
        "Ignore this bank transaction?",
        isPresented: $showingIgnoreConfirmation,
        titleVisibility: .visible
      ) {
        Button("Ignore transaction", role: .destructive) { ignoreImport() }
      } message: {
        Text("It will not appear in Spending or affect your budget.")
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
          Button("Update imported transaction") {
            possibleImportedMatchIDs = []
            save(matching: id)
          }
        }
        Button("Add separate transaction") {
          possibleImportedMatchIDs = []
          save(allowSeparate: true)
        }
        Button("Cancel", role: .cancel) { possibleImportedMatchIDs = [] }
      } message: {
        Text("An imported transaction may already represent this payment. Updating it keeps one ledger entry and uses the details you entered.")
      }
      .alert("Couldn’t save transaction", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .onChange(of: payee) { _, _ in applyPayeeRule() }
      .onChange(of: kind) { _, _ in applyPayeeRule() }
      .task(id: PayeeDefaultsTrigger(payee: payee, kind: kind)) {
        await applyLastUsedDefaults()
      }
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

  /// Explains the fields when something needs it; shown under the main section so Notes stays last.
  private var fieldsFootnote: String? {
    if (kind != .transfer || needsEnvelopeForTransfer) && kind == .expense && envelopeID == nil {
      return "Choose an envelope before saving this expense."
    }
    if kind != .transfer && (selectedAccount?.kind == .asset || selectedAccount?.kind == .liability) {
      return "Envelopes on tracking accounts are for reference and don't change your budget."
    }
    return nil
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

  /// Fills the account and envelope from the last transaction with this payee,
  /// without replacing anything the person chose themselves.
  private func applyLastUsedDefaults() async {
    guard kind != .transfer, !payee.isEmpty else { return }
    let lastUsed = try? await PayeeDirectoryRepository(modelContainer: modelContext.container)
      .lastUsed(payee: payee, kind: kind, excluding: transaction?.id)
    guard !Task.isCancelled else { return }

    if transaction == nil && scheduledDraft == nil
        && (accountID == defaultAccountID || accountID == autoFilledAccountID) {
      let suggested = lastUsed.flatMap { used in accounts.first { $0.id == used.accountID }?.id }
      accountID = suggested ?? defaultAccountID
      autoFilledAccountID = suggested
    }

    if kind == .expense && envelopeID == nil,
       let suggested = lastUsed?.envelopeID,
       envelopes.contains(where: { $0.id == suggested && !$0.isHidden && $0.paymentAccountID == nil }) {
      envelopeID = suggested
      autoAssignedEnvelopeID = suggested
    }
  }

  private func save(allowSeparate: Bool = false, matching importedID: UUID? = nil) {
    guard let account = selectedAccount, amountMinor > 0 else {
      errorMessage = "Choose an account and enter an amount greater than zero."
      return
    }
    let minor = amountMinor
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

  private func ignoreImport() {
    guard let importRecord else { return }
    do {
      try SimpleFINSyncCoordinator.shared.resolve(importRecord, as: .ignore, in: modelContext)
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

private struct PayeeDefaultsTrigger: Equatable {
  var payee: String
  var kind: BudgetTransactionKind
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
      Text("Scheduled bill")
    } footer: {
      Text("Linking marks this bill recorded without creating another transaction.")
    }
    .listRowBackground(Bow.card)
  }
}

/// The card at the top of the review sheet: where the transaction came from and why it's here.
private struct ReviewContextCard: View {
  var transaction: BudgetTransaction
  var record: SimpleFINImportRecord?
  var accountName: String?

  private var origin: String? {
    if record?.origin == .bankFile || transaction.sourceRaw == "bankFile" { return "From a bank file" }
    return transaction.isFromBank ? "From your bank" : nil
  }

  private var context: String {
    [origin, accountName, transaction.date.formatted(.dateTime.month(.abbreviated).day())]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  var body: some View {
    BowContextCard(
      name: transaction.payee.isEmpty ? "Bank transaction" : transaction.payee,
      context: context
    ) {
      MerchantLogoView(
        merchantName: transaction.payee, domain: transaction.merchantDomain,
        kind: transaction.kind, size: 44, style: .glossy
      )
    } trailing: {
      if transaction.needsApproval {
        StatusPill.needsReview
      } else {
        StatusPill(text: "Choose an envelope", state: .needs)
      }
    }
  }
}

/// Date row destination: a full calendar for picking the transaction's date.
private struct TransactionDatePickerScreen: View {
  var title: String
  @Binding var date: Date

  var body: some View {
    Form {
      DatePicker(title, selection: $date, in: Date.distantPast...Date.distantFuture,
                 displayedComponents: .date)
        .datePickerStyle(.graphical)
        .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
