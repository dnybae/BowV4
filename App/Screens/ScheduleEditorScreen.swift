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
  @State private var notes: String
  @State private var isActive: Bool
  @State private var errorMessage: String?
  @State private var showingDelete = false

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
    _frequency = State(initialValue: schedule?.frequency ?? draft?.frequency ?? .monthly)
    _notes = State(initialValue: schedule?.notes ?? "")
    _isActive = State(initialValue: schedule?.isActive ?? true)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Transaction") {
          Picker("Type", selection: $kind) {
            ForEach(BudgetTransactionKind.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)
          if kind != .transfer {
            TextField("Payee", text: $payee)
              .textInputAutocapitalization(.words)
          }
          CurrencyAmountField("Expected amount", minor: $amountMinor, currencyCode: currencyCode)
          AccountSelectionField(title: "Account", selection: $accountID, accounts: accounts)
          if kind == .transfer {
            AccountSelectionField(title: "To account", selection: $destinationID, accounts: accounts, excludingID: accountID)
          }
          if kind != .transfer || (accounts.first { $0.id == accountID }?.kind == .cash &&
              [.asset, .liability].contains(accounts.first { $0.id == destinationID }?.kind)) {
            EnvelopeSelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "No envelope"
            )
            if kind == .expense && envelopeID == nil {
              Text("Choose an envelope for this scheduled expense.")
                .font(.footnote)
                .foregroundStyle(Bow.inkSoft)
            }
          }
        }
        .listRowBackground(Bow.card)
        Section("Schedule") {
          DatePicker("First due", selection: $startDate, displayedComponents: .date)
          Picker("Repeats", selection: $frequency) {
            ForEach(ScheduleFrequency.allCases) { value in
              Text(value.title).tag(value)
            }
          }
          .pickerStyle(.menu)
          if schedule != nil {
            Toggle("Active", isOn: $isActive)
          }
        }
        .listRowBackground(Bow.card)
        Section("Notes") {
          TextField("Optional notes", text: $notes, axis: .vertical)
            .lineLimit(2...4)
        }
        .listRowBackground(Bow.card)
        if schedule != nil {
          Section {
            Button("Delete schedule", role: .destructive) { showingDelete = true }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle(schedule == nil ? "New schedule" : "Edit schedule")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
      }
      .confirmationDialog("Delete this schedule?", isPresented: $showingDelete) {
        Button("Delete schedule", role: .destructive) { delete() }
      } message: {
        Text("Previously recorded transactions will remain in your ledger.")
      }
      .alert("Couldn’t save schedule", isPresented: Binding(
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
    let item = schedule ?? BudgetSchedule(
      payee: payee,
      amountMinor: minor,
      accountID: accountID,
      envelopeID: envelopeID,
      startDate: startDate,
      frequency: frequency,
      notes: notes
    )
    let recurrenceChanged = schedule != nil && (
      !Calendar.current.isDate(item.startDate, inSameDayAs: startDate)
        || item.frequency != frequency || (!isActive && item.isActive)
    )
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
    item.frequencyRaw = frequency.rawValue
    item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    item.isActive = isActive
    if recurrenceChanged {
      for occurrence in occurrences where occurrence.scheduleID == item.id {
        modelContext.delete(occurrence)
      }
      item.reviewedThrough = Calendar.current.date(byAdding: .day, value: -1, to: Date())
    }
    if schedule == nil { modelContext.insert(item) }
    do {
      try modelContext.save()
      try? ScheduleReviewPlanner().refresh(in: modelContext)
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      dismiss()
    } catch { errorMessage = error.localizedDescription }
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
