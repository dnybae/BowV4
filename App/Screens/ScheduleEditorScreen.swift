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
  @State private var amount: String
  @State private var accountID: UUID?
  @State private var envelopeID: UUID?
  @State private var startDate: Date
  @State private var frequency: ScheduleFrequency
  @State private var notes: String
  @State private var isActive: Bool
  @State private var errorMessage: String?
  @State private var showingDelete = false

  init(schedule: BudgetSchedule?, accounts: [BudgetAccount], envelopes: [BudgetEnvelope], currencyCode: String) {
    self.schedule = schedule
    self.accounts = accounts
    self.envelopes = envelopes
    self.currencyCode = currencyCode
    _payee = State(initialValue: schedule?.payee ?? "")
    _amount = State(initialValue: schedule.map { BudgetMoney.editable($0.amountMinor) } ?? "")
    _accountID = State(initialValue: schedule?.accountID ?? accounts.first?.id)
    _envelopeID = State(initialValue: schedule?.envelopeID)
    _startDate = State(initialValue: schedule?.startDate ?? Date())
    _frequency = State(initialValue: schedule?.frequency ?? .monthly)
    _notes = State(initialValue: schedule?.notes ?? "")
    _isActive = State(initialValue: schedule?.isActive ?? true)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Payment") {
          TextField("Payee", text: $payee)
            .textInputAutocapitalization(.words)
          TextField("Expected amount", text: $amount)
            .keyboardType(.decimalPad)
          AccountSelectionField(title: "Account", selection: $accountID, accounts: accounts)
          CategorySelectionField(
            title: "Category", selection: $envelopeID,
            envelopes: envelopes, noneTitle: "No Category"
          )
        }
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
        Section("Notes") {
          TextField("Optional notes", text: $notes, axis: .vertical)
            .lineLimit(2...4)
        }
        if schedule != nil {
          Section {
            Button("Delete Schedule", role: .destructive) { showingDelete = true }
          }
        }
      }
      .navigationTitle(schedule == nil ? "New Scheduled Bill" : "Edit Scheduled Bill")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
      }
      .confirmationDialog("Delete this schedule?", isPresented: $showingDelete) {
        Button("Delete Schedule", role: .destructive) { delete() }
      } message: {
        Text("Previously recorded transactions will remain in your ledger.")
      }
      .alert("Couldn’t Save Schedule", isPresented: Binding(
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
    guard let minor = BudgetMoney.parseMinor(amount), minor > 0,
          !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "Enter a payee and an expected amount greater than zero."
      return
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
    item.payee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
    item.amountMinor = minor
    item.accountID = accountID
    item.envelopeID = envelopeID
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
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }
}
