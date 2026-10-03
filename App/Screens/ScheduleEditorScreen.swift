import SwiftUI
import SwiftData

struct ScheduleEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var occurrences: [BudgetScheduleOccurrence]
  var schedule: BudgetSchedule?
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  @State private var payee: String
  @State private var amountMinor: Int64
  @State private var accountID: UUID?
  @State private var destinationID: UUID?
  @State private var kind: BudgetTransactionKind
  @State private var envelopeID: UUID?
  @State private var startDate: Date
  @State private var frequency: ScheduleFrequency
  @State private var isRecurring: Bool
  @State private var notes: String
  @State private var isActive: Bool
  @State private var errorMessage: String?
  @State private var showingDelete = false
  @State private var showingPayeeSelection = false
  @State private var initialFields: ScheduleFields?
  @Environment(\.bowToasts) private var toasts

  init(
    schedule: BudgetSchedule?, draft: ScheduleDraft? = nil,
    accounts: [BudgetAccount], envelopes: [BudgetEnvelope], currencyCode: String
  ) {
    self.schedule = schedule
    self.accounts = accounts
    self.envelopes = envelopes
    self.currencyCode = currencyCode
    _payee = State(initialValue: schedule?.payee ?? draft?.payee ?? "")
    _amountMinor = State(initialValue: schedule.map { abs($0.amountMinor) } ?? draft?.amountMinor ?? 0)
    _accountID = State(initialValue: schedule?.accountID ?? draft?.accountID ?? accounts.first?.id)
    _destinationID = State(initialValue: schedule?.transferAccountID)
    _kind = State(initialValue: schedule?.kind ?? .expense)
    _envelopeID = State(initialValue: schedule?.envelopeID ?? draft?.envelopeID)
    _startDate = State(initialValue: schedule?.startDate ?? draft?.startDate ?? Date())
    let initialFrequency = schedule?.frequency ?? draft?.frequency ?? .monthly
    _frequency = State(initialValue: initialFrequency == .once ? .monthly : initialFrequency)
    _isRecurring = State(initialValue: initialFrequency != .once)
    _notes = State(initialValue: schedule?.notes ?? "")
    _isActive = State(initialValue: schedule?.isActive ?? true)
  }

  private var fields: ScheduleFields {
    ScheduleFields(payee: payee, amountMinor: amountMinor, accountID: accountID, destinationID: destinationID,
                   kind: kind, envelopeID: envelopeID, startDate: startDate, frequency: isRecurring ? frequency : .once,
                   notes: notes, isActive: isActive)
  }

  private var hasChanges: Bool {
    guard let initialFields else { return false }
    return fields != initialFields
  }

  /// Expenses and inflows use an envelope; a transfer only does when it moves cash to a tracking account.
  private var needsEnvelope: Bool {
    kind != .transfer || (accounts.first { $0.id == accountID }?.kind == .cash &&
      [.asset, .liability].contains(accounts.first { $0.id == destinationID }?.kind))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: Bow.Space.s4) {
            CurrencyAmountField("Amount", minor: $amountMinor, currencyCode: currencyCode, style: .editorHero)
            Picker("Type", selection: $kind) {
              ForEach(BudgetTransactionKind.allCases) { option in
                Text(option.title).tag(option)
              }
            }
            .pickerStyle(.segmented)
          }
          .padding(.bottom, Bow.Space.s2)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        Section {
          if kind != .transfer {
            // The same payee picker as a transaction, with logos and payee rules.
            Button {
              showingPayeeSelection = true
            } label: {
              HStack(spacing: Bow.Space.s3) {
                BowFieldTitle(title: kind == .expense ? "Payee" : "Source", systemImage: "person")
                Spacer(minLength: Bow.Space.s3)
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
            .accessibilityLabel("Payee, \(payee.isEmpty ? "Choose a payee" : payee)")
          }
          if needsEnvelope {
            EnvelopeSelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "No envelope", systemImage: "square.grid.2x2"
            )
          }
          AccountSelectionField(title: kind == .transfer ? "From account" : "Account",
                                selection: $accountID, accounts: accounts, systemImage: "creditcard")
          if kind == .transfer {
            AccountSelectionField(title: "To account", selection: $destinationID, accounts: accounts,
                                  excludingID: accountID, systemImage: "arrow.right")
          }
          BowNotesRow(notes: $notes)
        } footer: {
          Group {
            if needsEnvelope && kind == .expense && envelopeID == nil {
              Text("Choose an envelope for this scheduled expense.")
            }
          }
          .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
        Section {
          NavigationLink {
            BowDatePickerScreen(title: "Date", date: $startDate)
          } label: {
            BowTileValueRow("Date", systemImage: "calendar",
                            value: startDate.formatted(date: .abbreviated, time: .omitted))
          }
          Toggle(isOn: $isRecurring) {
            Label("Recurring", systemImage: "repeat").labelStyle(.bowTile)
          }
          .accessibilityLabel("Recurring")
          if isRecurring {
            Picker(selection: $frequency) {
              ForEach(ScheduleFrequency.recurringCases) { value in
                Text(value.title).tag(value)
              }
            } label: {
              Label("Repeats", systemImage: "repeat").labelStyle(.bowTile)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Repeats")
          }
          if schedule != nil {
            Toggle(isOn: $isActive) {
              Label("Active", systemImage: "bolt").labelStyle(.bowTile)
            }
          }
        }
        .listRowBackground(Bow.card)
        if isRecurring {
          Section {
            Text("Repeats from the chosen date. Missed occurrences won’t be added when you change or resume a schedule.")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
          }
          .listRowBackground(Color.clear)
        }
        if schedule != nil {
          BowDestructiveSection("Delete schedule") { showingDelete = true }
        }
      }
      .bowListBackground()
      .bowEditorSheet(hasChanges: hasChanges)
      .onAppear { if initialFields == nil { initialFields = fields } }
      .navigationTitle(schedule == nil ? "New transaction" : "Scheduled transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
      }
      .safeAreaInset(edge: .bottom) {
        BowBottomAction(schedule == nil ? (Calendar.current.isDateInToday(startDate) || startDate < Date() ? "Add transaction" : "Schedule transaction") : "Save changes",
                        isEnabled: amountMinor > 0) { save() }
      }
      .sheet(isPresented: $showingPayeeSelection) {
        PayeeSelectionSheet(selectedName: payee) { selected in
          payee = selected.name
          if envelopeID == nil, let defaultEnvelopeID = selected.defaultEnvelopeID {
            envelopeID = defaultEnvelopeID
          }
          showingPayeeSelection = false
        }
      }
      .confirmationDialog("Delete this schedule?", isPresented: $showingDelete) {
        Button("Delete schedule", role: .destructive) { delete() }
      } message: {
        Text("Previously recorded transactions will remain in your ledger.")
      }
      .bowErrorAlert("Couldn’t save schedule", message: $errorMessage)
    }
  }

  private func save() {
    guard amountMinor > 0,
          kind == .transfer || !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "Enter a payee and an expected amount greater than zero."
      return
    }
    let minor = amountMinor
    guard let source = accounts.first(where: { $0.id == accountID }) else {
      errorMessage = "Choose an account."
      return
    }
    if kind == .expense && envelopeID == nil {
      errorMessage = BudgetCommandError.expenseNeedsEnvelope.localizedDescription
      return
    }
    if kind == .transfer {
      guard let destination = accounts.first(where: { $0.id == destinationID }),
            destination.id != source.id, destination.currencyCode == source.currencyCode,
            source.kind != .credit else {
        errorMessage = "Choose a valid transfer destination. Pay credit cards from a cash account."
        return
      }
      if source.kind == .cash && [.asset, .liability].contains(destination.kind) && envelopeID == nil {
        errorMessage = "Choose an envelope for a transfer to a tracking account."
        return
      }
    }
    let effectiveFrequency: ScheduleFrequency = isRecurring ? frequency : .once
    guard let item = schedule else {
      do {
        try TransactionScheduling.save(
          kind: kind, account: source,
          destination: accounts.first { $0.id == destinationID },
          envelopeID: kind == .transfer && !needsEnvelope ? nil : envelopeID,
          amountMinor: minor, payee: payee, notes: notes,
          timing: TransactionTiming(date: startDate, isRecurring: isRecurring, frequency: frequency),
          in: modelContext
        )
        toasts?.show(.saved("Saved · \(payee)"))
        dismiss()
      } catch { errorMessage = error.localizedDescription }
      return
    }
    let recurrenceChanged = !Calendar.current.isDate(item.startDate, inSameDayAs: startDate)
      || item.frequency != effectiveFrequency || item.isActive != isActive
    item.payee = kind == .transfer
      ? "Transfer to \(accounts.first(where: { $0.id == destinationID })?.name ?? "Account")"
      : payee.trimmingCharacters(in: .whitespacesAndNewlines)
    item.amountMinor = minor
    item.accountID = accountID
    item.transferAccountID = kind == .transfer ? destinationID : nil
    item.kindRaw = kind.rawValue
    let needsEnvelope = kind != .transfer || (source.kind == .cash &&
      [.asset, .liability].contains(accounts.first { $0.id == destinationID }?.kind))
    item.envelopeID = needsEnvelope ? envelopeID : nil
    item.startDate = startDate
    item.frequencyRaw = effectiveFrequency.rawValue
    item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    item.isActive = isActive
    if recurrenceChanged {
      for occurrence in occurrences where occurrence.scheduleID == item.id {
        modelContext.delete(occurrence)
      }
      item.reviewedThrough = Calendar.current.startOfDay(for: Date())
    }
    do {
      try modelContext.save()
      try? ScheduleReviewPlanner().refresh(in: modelContext)
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      toasts?.show(.saved("Saved · \(item.payee) · \(effectiveFrequency == .once ? "One-time" : effectiveFrequency.title)"))
      dismiss()
    } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
  }

  private func delete() {
    guard let schedule else { return }
    for occurrence in occurrences where occurrence.scheduleID == schedule.id {
      modelContext.delete(occurrence)
    }
    modelContext.delete(schedule)
    do {
      try modelContext.save()
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }
}

struct ScheduleDraft: Identifiable {
  var id = UUID()
  var payee: String
  var amountMinor: Int64
  var accountID: UUID?
  var envelopeID: UUID?
  var startDate: Date
  var frequency: ScheduleFrequency
}

/// The editable fields, compared to what the sheet opened with.
private struct ScheduleFields: Equatable {
  var payee: String
  var amountMinor: Int64
  var accountID: UUID?
  var destinationID: UUID?
  var kind: BudgetTransactionKind
  var envelopeID: UUID?
  var startDate: Date
  var frequency: ScheduleFrequency
  var notes: String
  var isActive: Bool
}
