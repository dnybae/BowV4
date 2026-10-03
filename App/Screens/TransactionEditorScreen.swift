import SwiftUI
import SwiftData

/// The one transaction sheet. Adding, editing, approving a bank item, entering a pending one and
/// entering a scheduled bill all use the same fields in the same order. Only the status under
/// the amount, one context row and the bottom button change with the sheet's purpose.
struct TransactionEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  @Query private var schedules: [BudgetSchedule]
  /// The bank records behind the transaction being edited.
  @Query private var importRecords: [SimpleFINImportRecord]
  var transaction: BudgetTransaction?
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var payees: [BudgetPayee]
  var currencyCode: String
  var scheduledDraft: ScheduledTransactionDraft?
  /// A posted bank item not yet in the budget.
  var reviewRecord: SimpleFINImportRecord?
  /// A pending bank item not yet entered.
  var pendingRecord: SimpleFINImportRecord?
  /// A scheduled bill the bank item lines up with; approving records that date of it.
  var relatedOccurrence: BudgetScheduleOccurrence?
  var relatedSchedule: BudgetSchedule?
  /// Opens the schedule editor for the bill being entered.
  var onEditSchedule: ((UUID) -> Void)?
  /// Fixed when the sheet opens, so it doesn't change on save.
  @State private var purpose: TransactionSheetPurpose
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
  /// Transactions you entered that this bank item could be.
  @State private var candidates: [BudgetTransaction] = []
  /// The transaction the bank item surely is. Nil adds the bank item as its own transaction.
  @State private var matchedID: UUID?
  /// The fields as the bank sent them, to go back to on Unmatch.
  @State private var bankFields: EditorFields?
  /// The matched transaction's own fields, to tell whether anything was changed on top of them.
  @State private var matchFields: EditorFields?
  @State private var didLoadMatch = false
  /// What the sheet opened with, to tell whether anything was changed before Cancel or a swipe down.
  @State private var initialFields: EditorFields?

  init(
    subject: TransactionSheetSubject,
    relatedOccurrence: BudgetScheduleOccurrence? = nil,
    relatedSchedule: BudgetSchedule? = nil,
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    payees: [BudgetPayee],
    currencyCode: String,
    onEditSchedule: ((UUID) -> Void)? = nil
  ) {
    var transaction: BudgetTransaction?
    var scheduledDraft: ScheduledTransactionDraft?
    var reviewRecord: SimpleFINImportRecord?
    var pendingRecord: SimpleFINImportRecord?
    var preferredAccountID: UUID?
    let purpose: TransactionSheetPurpose
    switch subject {
    case .new(let accountID):
      preferredAccountID = accountID
      purpose = .add
    case .existing(let existing):
      transaction = existing
      purpose = TransactionSheetPurpose(existingNeedsReview: existing.needsApproval
        || existing.needsEnvelope)
    case .bankItem(let record):
      reviewRecord = record
      purpose = .approve
    case .pendingItem(let record):
      pendingRecord = record
      purpose = .enterPending
    case .scheduled(let draft):
      scheduledDraft = draft
      purpose = .enterScheduled
    }
    self.transaction = transaction
    self.accounts = accounts
    self.envelopes = envelopes
    self.payees = payees
    self.currencyCode = currencyCode
    self.scheduledDraft = scheduledDraft
    self.reviewRecord = reviewRecord
    self.pendingRecord = pendingRecord
    self.relatedOccurrence = relatedOccurrence
    self.relatedSchedule = relatedSchedule
    self.onEditSchedule = onEditSchedule
    _purpose = State(initialValue: purpose)

    let bank = reviewRecord ?? pendingRecord
    // A bank transfer leg that lines up with a scheduled transfer is entered as that transfer.
    let scheduledTransfer = reviewRecord != nil && relatedSchedule?.kind == .transfer ? relatedSchedule : nil
    let bankKind: BudgetTransactionKind? = bank.map { $0.amountMinor < 0 ? .expense : .inflow }
    _kind = State(initialValue: transaction?.kind ?? scheduledDraft?.kind
      ?? (scheduledTransfer != nil ? .transfer : nil) ?? bankKind ?? .expense)
    let openAccounts = accounts.filter { $0.closedAt == nil }
    let fallbackAccountID: UUID? = openAccounts.first(where: { $0.kind == .cash })?.id
      ?? openAccounts.first(where: { $0.kind == .credit })?.id
      ?? openAccounts.first?.id
    let defaultAccountID: UUID? = transaction?.accountID ?? scheduledDraft?.accountID
      ?? scheduledTransfer?.accountID ?? bank?.localAccountID
      ?? preferredAccountID ?? fallbackAccountID
    self.defaultAccountID = defaultAccountID
    _accountID = State(initialValue: defaultAccountID)
    _destinationID = State(initialValue: transaction?.transferAccountID
      ?? scheduledDraft?.transferAccountID ?? scheduledTransfer?.transferAccountID)
    _envelopeID = State(initialValue: transaction?.envelopeID ?? scheduledDraft?.envelopeID
      ?? (reviewRecord != nil ? relatedSchedule?.envelopeID : nil))
    _amountMinor = State(initialValue: transaction.map { abs($0.amountMinor) }
      ?? scheduledDraft.map { abs($0.amountMinor) } ?? scheduledTransfer.map { abs($0.amountMinor) }
      ?? bank.map { abs($0.amountMinor) } ?? 0)
    _payee = State(initialValue: transaction?.payee ?? scheduledDraft?.payee
      ?? scheduledTransfer?.payee ?? bank?.payee ?? "")
    _merchantDomain = State(initialValue: transaction?.merchantDomain)
    // Notes are only ever what you type: never the bank's memo or the schedule's note.
    _notes = State(initialValue: transaction?.notes ?? "")
    _date = State(initialValue: transaction?.date ?? scheduledDraft?.date ?? bank?.date ?? Date())
    // A new transaction has no bank records; the placeholder ID matches none.
    let transactionID: UUID? = transaction?.id ?? UUID()
    _importRecords = Query(filter: #Predicate<SimpleFINImportRecord> { $0.transactionID == transactionID })
  }

  /// The posted bank record an imported transaction came from.
  private var importRecord: SimpleFINImportRecord? {
    guard transaction != nil else { return nil }
    return importRecords.first { $0.status == .imported && $0.bankState == .posted }
  }

  /// The bank transaction this one was matched with.
  private var linkedRecord: SimpleFINImportRecord? {
    importRecords.first { $0.status == .linked }
  }

  /// A pending bank authorization for a transaction you already entered.
  private var pendingAtBankRecord: SimpleFINImportRecord? {
    importRecords.first { $0.bankState == .pending && $0.isVisiblePending }
  }

  /// The posted bank item being approved.
  private var bankRecord: SimpleFINImportRecord? { reviewRecord ?? importRecord }

  /// Preserve the bank's original values alongside the editable budget transaction.
  private var bankDetailRecords: [SimpleFINImportRecord] {
    var records = importRecords
    for record in [reviewRecord, pendingRecord].compactMap({ $0 }) {
      if !records.contains(where: { $0.id == record.id }) { records.append(record) }
    }
    return records.filter {
      $0.status != .ignored && ($0.bankState == .posted || $0.isVisiblePending)
    }.sorted {
      if $0.date != $1.date { return $0.date > $1.date }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  private var matchedCandidate: BudgetTransaction? {
    candidates.first { $0.id == matchedID }
  }

  /// The bank decides which account a bank item is in; a match keeps the account you entered.
  private var locksAccount: Bool {
    matchedID != nil || (purpose == .approve && bankRecord != nil) || purpose == .enterPending
  }

  private var status: TransactionSheetStatus? {
    TransactionSheetStatus(
      purpose: purpose,
      isPendingAtBank: pendingAtBankRecord != nil,
      // A bank match clears it, including a transfer matched on its receiving side.
      isCleared: transaction?.isCleared == true || linkedRecord != nil,
      dueDate: scheduledDraft?.scheduledFor
    )
  }

  /// A bill Bow entered on its due date that the bank hasn't confirmed yet: skipping undoes it.
  private var enteredBillScheduleID: UUID? {
    guard purpose == .edit, let transaction, transaction.scheduledFor != nil,
          status == .uncleared else { return nil }
    return transaction.scheduleID
  }

  /// The schedule whose date this sheet can skip: a bill waiting to be entered, or one Bow entered.
  private var skippableScheduleID: UUID? {
    purpose == .enterScheduled ? scheduledDraft?.scheduleID : enteredBillScheduleID
  }

  private var statusPill: StatusPill? {
    guard let status else { return nil }
    switch status {
    case .needsReview: return .needsReview
    case .pendingAtBank: return .pendingAtBank
    case .dueToday, .due: return .scheduled(status.text)
    case .overdue: return StatusPill(text: status.text, state: .needs)
    case .cleared: return .cleared
    case .uncleared: return StatusPill(text: status.text, state: .empty)
    }
  }

  private var fields: EditorFields {
    EditorFields(kind: kind, accountID: accountID, destinationID: destinationID, envelopeID: envelopeID,
                 amountMinor: amountMinor, payee: payee, notes: notes, date: date, isScheduled: isScheduled,
                 recurrence: recurrence, merchantDomain: merchantDomain,
                 linkScheduledBill: linkScheduledBill, matchedID: matchedID)
  }

  private func apply(_ fields: EditorFields) {
    kind = fields.kind
    accountID = fields.accountID
    destinationID = fields.destinationID
    envelopeID = fields.envelopeID
    amountMinor = fields.amountMinor
    payee = fields.payee
    notes = fields.notes
    date = fields.date
    merchantDomain = fields.merchantDomain
    matchedID = fields.matchedID
  }

  private var hasChanges: Bool {
    guard let initialFields else { return false }
    return fields != initialFields
  }

  private var primaryTitle: String {
    purpose.primaryTitle(signedAmount: signedAmountText, amountIsZero: amountMinor == 0,
                         isScheduling: isScheduled)
  }

  private var isPrimaryEnabled: Bool {
    purpose == .edit ? canSave && hasChanges : canSave
  }

  private var signedAmountText: String {
    let signed = kind == .expense ? -amountMinor : amountMinor
    return BudgetMoney.formatted(signed, currencyCode: currencyCode, showsPlusSign: kind == .inflow)
  }

  /// "−$12.50 · Groceries", for the confirmation after saving.
  private var savedSummary: String {
    let destination = kind == .transfer
      ? accounts.first { $0.id == destinationID }?.name
      : envelopes.first { $0.id == envelopeID }?.name ?? (payee.isEmpty ? nil : payee)
    return [signedAmountText, destination].compactMap { $0 }.joined(separator: " · ")
  }

  private var canSave: Bool {
    accountID != nil && amountMinor != 0 && !(kind == .expense && envelopeID == nil && !isHistory)
      && (kind != .transfer || (destinationID != nil && selectedAccount?.kind != .credit
        && (!needsEnvelopeForTransfer || envelopeID != nil)))
  }

  /// Dated before the account's starting balance: kept as history, so no envelope is needed.
  private var isHistory: Bool {
    guard let selectedAccount else { return false }
    return BudgetCommands.isBeforeStart(
      date: date, account: selectedAccount,
      destination: kind == .transfer ? accounts.first { $0.id == destinationID } : nil
    )
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

  private var chosenEnvelopeID: UUID? {
    kind == .transfer && !needsEnvelopeForTransfer ? nil : envelopeID
  }

  private var envelopeNoneTitle: String {
    if kind == .inflow {
      return selectedAccount?.kind == .cash ? "Ready to Assign" : "No envelope"
    }
    return "Needs an envelope"
  }

  /// A scheduled bill this transaction could be recorded as, offered with a toggle.
  private var matchingSchedule: BudgetSchedule? {
    guard relatedOccurrence == nil, matchedID == nil,
          let transaction, transaction.needsApproval, transaction.scheduleID == nil,
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
        Section {
          VStack(spacing: Bow.Space.s4) {
            CurrencyAmountField("Amount", minor: $amountMinor, currencyCode: currencyCode, style: .editorHero,
                                focusOnAppear: purpose == .add)
              // A match uses the posted bank amount.
              .disabled(matchedID != nil)
            if let statusPill {
              statusPill
            }
            Picker("Type", selection: $kind) {
              ForEach(BudgetTransactionKind.allCases) { option in
                Text(option.title).tag(option)
              }
            }
            .pickerStyle(.segmented)
            .disabled(purpose.locksType || matchedID != nil)
          }
          .padding(.bottom, Bow.Space.s2)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        Section {
          fieldRows
        } footer: {
          Group {
            if let fieldsFootnote {
              Text(fieldsFootnote)
            }
          }
          .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
        Section {
          BowNotesRow(notes: $notes)
        }
        .listRowBackground(Bow.card)
        contextSection
        if let scheduleID = skippableScheduleID {
          Section {
            Button("Skip this date") { skipScheduledDate() }
            if let onEditSchedule {
              Button("Edit schedule") { onEditSchedule(scheduleID) }
            }
          } footer: {
            Group {
              Text(purpose == .enterScheduled
                ? "Skipping keeps the schedule active for future dates."
                : "Bow entered this bill on its due date. Skipping removes it from your budget; the schedule stays active for future dates.")
            }
            .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        }
        if purpose == .add {
          Section {
            Toggle(isOn: $isScheduled) {
              Label("Schedule for later", systemImage: "repeat").labelStyle(.bowTile)
            }
            if isScheduled {
              Picker(selection: $recurrence) {
                ForEach(ScheduleFrequency.allCases) { frequency in
                  Text(frequency.title).tag(frequency)
                }
              } label: {
                Label("Repeats", systemImage: "arrow.clockwise").labelStyle(.bowTile)
              }
              .pickerStyle(.menu)
            }
          } footer: {
            Group {
              if isScheduled {
                Text("Scheduled entries appear on the calendar and affect balances only when recorded.")
              }
            }
            .font(.bowFootnote)
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

        ForEach(bankDetailRecords) { record in
          BankTransactionDetailsSection(
            record: record,
            accountName: accounts.first { $0.id == record.localAccountID }?.name ?? "Account",
            currencyCode: accounts.first { $0.id == record.localAccountID }?.currencyCode ?? currencyCode
          )
        }

        if purpose == .approve && bankRecord != nil {
          BowDestructiveSection("Ignore bank transaction") {
            showingIgnoreConfirmation = true
          }
        } else if transaction != nil && enteredBillScheduleID == nil {
          // An entered bill is removed with Skip this date instead, which does the same.
          BowDestructiveSection("Delete transaction") {
            showingDeleteConfirmation = true
          }
        }
      }
      .bowListBackground()
      .bowEditorSheet(hasChanges: hasChanges)
      .bowAnimation(value: matchedID)
      // One primary action, at the bottom, riding above the keyboard. No Save in the toolbar.
      .safeAreaInset(edge: .bottom) {
        BowBottomAction(isEnabled: isPrimaryEnabled, action: performPrimaryAction) {
          if let symbol = purpose.primarySystemImage {
            Label(primaryTitle, systemImage: symbol)
          } else {
            Text(primaryTitle)
          }
        }
      }
      .sensoryFeedback(.selection, trigger: payee)
      .navigationTitle(purpose == .add ? "New transaction" : "Transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
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
      .bowErrorAlert("Couldn’t save transaction", message: $errorMessage)
      .task(id: bankRecord?.id) { loadMatch() }
      .onAppear {
        // A bank item gets the envelope its payee usually goes to.
        if (reviewRecord != nil || pendingRecord != nil) && envelopeID == nil { applyPayeeRule() }
        if initialFields == nil { initialFields = fields }
      }
      .onChange(of: payee) { _, _ in applyPayeeRule() }
      .onChange(of: kind) { _, newKind in
        applyPayeeRule()
        // A transfer starts from a cash account; move off a card if one was chosen.
        if newKind == .transfer, selectedAccount?.kind == .credit, !locksAccount {
          accountID = accounts.first { $0.kind == .cash && $0.closedAt == nil }?.id
        }
      }
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

  /// Payee, Envelope, Account and Date: the same rows, in the same order, in every state.
  @ViewBuilder
  private var fieldRows: some View {
    if kind == .transfer {
      // Cards are paid by a transfer from a cash account, never the other way round.
      AccountSelectionField(title: "From account", selection: $accountID,
                            accounts: accounts.filter { $0.kind != .credit },
                            systemImage: "creditcard")
        .disabled(locksAccount)
      AccountSelectionField(
        title: "To account", selection: $destinationID,
        accounts: accounts, excludingID: accountID, systemImage: "arrow.right"
      )
      .disabled(locksAccount)
    } else {
      Button {
        showingPayeeSelection = true
      } label: {
        HStack(spacing: 12) {
          BowFieldTitle(title: kind == .expense ? "Payee" : "Source", systemImage: "person")
          Spacer(minLength: 12)
          Text(payee.isEmpty ? "Choose a payee" : payee)
            .foregroundStyle(payee.isEmpty ? Bow.inkSoft : Bow.ink)
            .lineLimit(1)
          Image(systemName: "chevron.right")
            .font(.bowFootnote.weight(.semibold))
            .foregroundStyle(Bow.inkFaint)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
      }
      .accessibilityLabel("\(kind == .expense ? "Payee" : "Source"), \(payee.isEmpty ? "Choose a payee" : payee)")
    }
    if kind != .transfer || needsEnvelopeForTransfer {
      EnvelopeSelectionField(
        title: "Envelope", selection: $envelopeID,
        envelopes: envelopes, noneTitle: envelopeNoneTitle, systemImage: "square.grid.2x2",
        // A new expense simply hasn't been given one yet; flag it only on saved transactions.
        highlightsNone: kind == .expense && purpose != .add,
        prompt: kind != .inflow && purpose == .add ? "Choose an envelope" : nil
      )
    }
    if kind != .transfer {
      if locksAccount {
        LabeledContent {
          Text(selectedAccount?.name ?? "Account")
        } label: {
          Label("Account", systemImage: "creditcard").labelStyle(.bowTile)
        }
      } else {
        AccountSelectionField(title: "Account", selection: $accountID, accounts: accounts,
                              systemImage: "creditcard")
      }
    }
    NavigationLink {
      BowDatePickerScreen(title: isScheduled ? "First due" : "Date", date: $date)
    } label: {
      LabeledContent {
        Text(date.formatted(date: .abbreviated, time: .omitted))
      } label: {
        Label(isScheduled ? "First due" : "Date", systemImage: "calendar")
          .labelStyle(.bowTile)
      }
    }
  }

  /// The one row that differs by state: the match, or the scheduled bill this becomes.
  @ViewBuilder
  private var contextSection: some View {
    if let candidate = matchedCandidate, let bankRecord {
      Section {
        NavigationLink {
          MatchDetailsScreen(
            entered: side(for: candidate, seenFrom: bankRecord), bank: side(for: bankRecord),
            unmatchFootnote: "Unmatching adds the bank transaction as a new one when you approve.",
            onUnmatch: unmatchBeforeApproving
          )
        } label: {
          matchRow(bankRecord)
        }
      }
      .listRowBackground(Bow.card)
    } else if purpose == .edit, let transaction, let linkedRecord {
      Section {
        NavigationLink {
          MatchDetailsScreen(
            entered: side(for: transaction, seenFrom: linkedRecord), bank: side(for: linkedRecord),
            unmatchFootnote: "Unmatching keeps your transaction and returns the bank transaction to review.",
            onUnmatch: { unmatch(linkedRecord) }
          )
        } label: {
          matchRow(linkedRecord)
        }
      }
      .listRowBackground(Bow.card)
    } else if let relatedSchedule, let relatedOccurrence {
      Section {
        LabeledContent {
          Text(relatedSchedule.payee.isEmpty ? "Scheduled" : relatedSchedule.payee)
        } label: {
          Label("Scheduled bill", systemImage: "calendar.badge.clock").labelStyle(.bowTile)
        }
      } footer: {
        Text("Approving records the \(relatedOccurrence.scheduledFor.formatted(.dateTime.month(.abbreviated).day())) date of this schedule.")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)
    } else if let matchingSchedule {
      ScheduledMatchSection(
        payee: matchingSchedule.payee, date: date,
        isLinked: $linkScheduledBill
      )
    }
  }

  private func matchRow(_ record: SimpleFINImportRecord) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        Text(record.payee.isEmpty ? "Bank transaction" : record.payee)
          .lineLimit(1)
        Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
          .font(.bowSubhead)
      }
    } label: {
      Label("Match details", systemImage: "link").labelStyle(.bowTile)
    }
  }

  private func side(for transaction: BudgetTransaction, seenFrom record: SimpleFINImportRecord) -> MatchDetailsScreen.Side {
    MatchDetailsScreen.Side(
      payee: TransactionRowModel.title(payee: transaction.payee, kind: transaction.kind),
      date: transaction.date,
      amountMinor: transaction.transferAccountID == record.localAccountID
        ? -transaction.amountMinor : transaction.amountMinor,
      currencyCode: currencyCode
    )
  }

  private func side(for record: SimpleFINImportRecord) -> MatchDetailsScreen.Side {
    MatchDetailsScreen.Side(
      payee: record.payee, date: record.date, amountMinor: record.amountMinor,
      currencyCode: currencyCode, isPending: record.bankState == .pending
    )
  }

  /// Explains the fields when something needs it; shown under the main section.
  private var fieldsFootnote: String? {
    if isHistory {
      return "This is before \(selectedAccount?.name ?? "the account")’s starting balance date, so it’s kept as history and doesn’t change the balance or budget."
    }
    if kind == .expense && envelopeID == nil {
      return "Choose an envelope before saving this expense."
    }
    if kind == .transfer && destinationID == nil {
      return "Choose the account the money goes to."
    }
    if needsEnvelopeForTransfer && envelopeID == nil {
      return "Choose the envelope that pays for this transfer."
    }
    if kind != .transfer && (selectedAccount?.kind == .asset || selectedAccount?.kind == .liability) {
      return "Envelopes on tracking accounts are for reference and don't change your budget."
    }
    if purpose == .enterPending {
      return "The final amount and date may change when it posts. Bow will match it then."
    }
    return nil
  }

  private func performPrimaryAction() {
    switch purpose {
    case .add, .edit, .enterScheduled: save()
    case .approve: approve()
    case .enterPending: enterPending()
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

  /// Fills the account and envelope from the last transaction with this payee,
  /// without replacing anything the person chose themselves.
  private func applyLastUsedDefaults() async {
    guard kind != .transfer, !payee.isEmpty else { return }
    let lastUsed = try? await PayeeDirectoryRepository(modelContainer: modelContext.container)
      .lastUsed(payee: payee, kind: kind, excluding: transaction?.id)
    guard !Task.isCancelled else { return }
    // Filling in on open isn't a change of yours, so Cancel shouldn't ask about it.
    let wasUnchanged = initialFields == nil || !hasChanges
    defer { if wasUnchanged { initialFields = fields } }

    // Only a new transaction's account is a guess; everything else already has its account.
    if purpose == .add && (accountID == defaultAccountID || accountID == autoFilledAccountID) {
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
    let linkedScheduleID = scheduledDraft?.scheduleID ?? relatedOccurrence?.scheduleID
      ?? (linkScheduledBill ? matchingSchedule?.id : nil)
    let linkedScheduledFor = scheduledDraft?.scheduledFor ?? relatedOccurrence?.scheduledFor
      ?? (linkScheduledBill && matchingSchedule != nil ? date : nil)
    if isScheduled && purpose == .add {
      do {
        try BudgetCommands.addSchedule(
          kind: kind, account: account, destination: destination,
          envelopeID: chosenEnvelopeID, amountMinor: minor, startDate: date,
          frequency: recurrence, payee: payee, notes: notes, in: modelContext
        )
        toasts?.show(.saved("Scheduled · \(savedSummary)"))
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
      let verb = switch purpose {
      case .approve: "Approved"
      case .edit: "Saved"
      case .add, .enterPending, .enterScheduled: transaction == nil ? "Added" : "Saved"
      }
      toasts?.show(.saved("\(verb) · \(savedSummary)"))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Finds what the bank item surely is. A sure match fills the sheet with the transaction you
  /// entered (matching keeps its payee, envelope and notes); otherwise nothing is suggested.
  private func loadMatch() {
    guard !didLoadMatch, purpose == .approve, let bankRecord else { return }
    didLoadMatch = true
    let wasUnchanged = initialFields == nil || !hasChanges
    do {
      let nearby = try BudgetTransactionLookup.near(
        accountID: bankRecord.localAccountID, date: bankRecord.date, days: 10, in: modelContext
      )
      let records = try modelContext.fetch(FetchDescriptor<SimpleFINImportRecord>())
      var possible = SimpleFINSyncCoordinator.shared.possibleMatches(
        for: bankRecord, among: nearby, records: records
      ).filter { $0.id != transaction?.id }
      // A scheduled transfer's bank leg can only match a transfer.
      if relatedSchedule?.kind == .transfer { possible = possible.filter { $0.kind == .transfer } }
      candidates = possible
      let sureID = BankMatchPicker().sureMatch(
        bankAmountMinor: bankRecord.amountMinor,
        linkedID: bankRecord.status == .review ? bankRecord.transactionID : nil,
        scheduleID: relatedSchedule?.id,
        among: possible.map { candidate in
          BankMatchPicker.Candidate(
            id: candidate.id,
            bankAmountMinor: candidate.transferAccountID == bankRecord.localAccountID
              ? -candidate.amountMinor : candidate.amountMinor,
            scheduleID: candidate.scheduleID
          )
        }
      )
      if let sureID, let candidate = possible.first(where: { $0.id == sureID }) {
        bankFields = fields
        var matched = fields
        matched.kind = candidate.kind
        matched.accountID = candidate.accountID
        matched.destinationID = candidate.transferAccountID
        matched.amountMinor = candidate.kind == .transfer
          ? abs(candidate.amountMinor) : abs(bankRecord.amountMinor)
        matched.payee = candidate.payee
        matched.merchantDomain = candidate.merchantDomain
        matched.notes = candidate.notes
        matched.date = candidate.date
        matched.matchedID = sureID
        matched.envelopeID = candidate.envelopeID
        matchFields = matched
        // Keep the suggested envelope when the entered transaction doesn't have one yet.
        if candidate.envelopeID == nil { matched.envelopeID = envelopeID }
        apply(matched)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    if wasUnchanged { initialFields = fields }
  }

  /// Unmatch before approving: back to the bank's own details, added as a new transaction.
  private func unmatchBeforeApproving() {
    guard let bankFields else { return }
    apply(bankFields)
  }

  /// Unmatch a saved match: your transaction stays, and the bank item goes back to review.
  private func unmatch(_ record: SimpleFINImportRecord) {
    do {
      try SimpleFINSyncCoordinator.shared.unmatch(record, in: modelContext)
      toasts?.show(.saved("Unmatched · bank transaction back in review"))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Approve: match the bank item to what you entered, or add it to the budget. Everything the
  /// sheet changes is saved together, so a failure leaves the bank item exactly as it was.
  private func approve() {
    guard let account = selectedAccount else {
      errorMessage = "Choose an account."
      return
    }
    let coordinator = SimpleFINSyncCoordinator.shared
    let message: String
    do {
      if let matchedID, let candidate = matchedCandidate, let bankRecord {
        try coordinator.resolve(
          bankRecord, as: .link(matchedID), envelopeID: envelopeID,
          scheduleID: relatedOccurrence?.scheduleID, scheduledFor: relatedOccurrence?.scheduledFor,
          in: modelContext, saving: false
        )
        if fields != matchFields {
          try BudgetCommands.updateTransaction(
            candidate, kind: candidate.kind, account: account,
            destination: accounts.first { $0.id == candidate.transferAccountID },
            envelopeID: chosenEnvelopeID, amountMinor: abs(candidate.amountMinor), date: date,
            payee: payee, merchantDomain: merchantDomain, notes: notes, in: modelContext, saving: false
          )
        }
        message = "Matched and approved"
      } else if let reviewRecord {
        if relatedSchedule?.kind == .transfer, let relatedOccurrence {
          // Records the scheduled transfer and matches this bank leg to it, in one step.
          let recorded = try BudgetCommands.addTransaction(
            kind: .transfer, account: account,
            destination: accounts.first { $0.id == destinationID },
            envelopeID: chosenEnvelopeID, amountMinor: amountMinor, date: date,
            payee: payee, notes: notes,
            scheduleID: relatedOccurrence.scheduleID, scheduledFor: relatedOccurrence.scheduledFor,
            in: modelContext, saving: false
          )
          try coordinator.resolve(
            reviewRecord, as: .link(recorded.id),
            scheduleID: relatedOccurrence.scheduleID, scheduledFor: relatedOccurrence.scheduledFor,
            in: modelContext, saving: false
          )
        } else {
          try coordinator.resolve(
            reviewRecord, as: .importNew, envelopeID: envelopeID,
            scheduleID: relatedOccurrence?.scheduleID, scheduledFor: relatedOccurrence?.scheduledFor,
            in: modelContext, saving: false
          )
          try applyEdits(madeTo: reviewRecord, account: account)
        }
        message = "Approved · \(savedSummary)"
      } else {
        save()
        return
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
      return
    }
    toasts?.show(.saved(message))
    dismiss()
  }

  /// Enter Now: puts a pending bank item in the budget before it posts, edits included, in one save.
  private func enterPending() {
    guard let pendingRecord, let account = selectedAccount else { return }
    do {
      try SimpleFINSyncCoordinator.shared.enterPending(
        pendingRecord, envelopeID: envelopeID, in: modelContext, saving: false
      )
      try applyEdits(madeTo: pendingRecord, account: account)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
      return
    }
    toasts?.show(.saved("Entered · \(savedSummary)"))
    dismiss()
  }

  /// Once a bank item is in the budget, applies anything changed in the sheet. Doesn't save.
  private func applyEdits(madeTo record: SimpleFINImportRecord, account: BudgetAccount) throws {
    let edited = payee != record.payee || !notes.isEmpty || merchantDomain != nil
      || amountMinor != abs(record.amountMinor)
      || !Calendar.current.isDate(date, inSameDayAs: record.date)
    guard edited,
          let added = try record.transactionID.flatMap({ try BudgetTransactionLookup.byID($0, in: modelContext) })
    else { return }
    try BudgetCommands.updateTransaction(
      added, kind: kind, account: account, destination: nil, envelopeID: envelopeID,
      amountMinor: amountMinor, date: date, payee: payee, merchantDomain: merchantDomain,
      notes: notes, in: modelContext, saving: false
    )
  }

  /// Skips this date of the bill. One Bow already entered is removed, undoing its effect on the
  /// budget; the schedule stays active either way.
  private func skipScheduledDate() {
    do {
      let undo: UndoableChanges.Action
      if purpose == .enterScheduled, let scheduledDraft {
        undo = try UndoableChanges.skip(scheduleID: scheduledDraft.scheduleID, date: scheduledDraft.scheduledFor, in: modelContext)
      } else if let transaction {
        undo = try UndoableChanges.delete(transaction, in: modelContext)
      } else { return }
      toasts?.show(.deleted("Skipped · \(payee.isEmpty ? "Scheduled bill" : payee)", undo: undo))
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private func ignoreImport() {
    guard let bankRecord else { return }
    do {
      let undo = try UndoableChanges.ignore(bankRecord, in: modelContext)
      toasts?.show(.deleted("Ignored · \(payee.isEmpty ? "Bank transaction" : payee)", undo: undo))
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private func delete() {
    guard let transaction else { return }
    do {
      let undo = try UndoableChanges.delete(transaction, in: modelContext)
      toasts?.show(.deleted("Deleted · \(savedSummary)", undo: undo))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// The editable fields, compared to what the sheet opened with.
private struct EditorFields: Equatable {
  var kind: BudgetTransactionKind
  var accountID: UUID?
  var destinationID: UUID?
  var envelopeID: UUID?
  var amountMinor: Int64
  var payee: String
  var notes: String
  var date: Date
  var isScheduled: Bool
  var recurrence: ScheduleFrequency
  var merchantDomain: String?
  var linkScheduledBill: Bool
  var matchedID: UUID?
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
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }
}
