import SwiftUI
import SwiftData

struct PayeeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var transactions: [BudgetTransaction]
  @Query private var schedules: [BudgetSchedule]
  @Query private var envelopes: [BudgetEnvelope]
  var entry: PayeeDirectory.Entry?
  var onSaved: () -> Void
  @State private var name: String
  @State private var exactMatchText: String
  @State private var defaultEnvelopeID: UUID?
  @State private var errorMessage: String?
  @State private var showingDelete = false

  init(entry: PayeeDirectory.Entry?, payee: BudgetPayee? = nil, onSaved: @escaping () -> Void = {}) {
    self.entry = entry
    self.onSaved = onSaved
    _name = State(initialValue: entry?.name ?? "")
    _exactMatchText = State(initialValue: payee?.exactMatchText ?? "")
    _defaultEnvelopeID = State(initialValue: payee?.defaultEnvelopeID)
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Payee") {
          TextField("Payee Name", text: $name)
            .textInputAutocapitalization(.words)
        }
        Section {
          Picker("Default Envelope", selection: $defaultEnvelopeID) {
            Text("None").tag(nil as UUID?)
            ForEach(envelopes.sorted {
              $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }) { envelope in
              Text(envelope.name).tag(Optional(envelope.id))
            }
          }
        } footer: {
          Text("Bow suggests this envelope when you enter this payee on an expense. You can always choose a different one.")
        }
        Section {
          TextField("Exact bank description", text: $exactMatchText)
            .textInputAutocapitalization(.characters)
        } footer: {
          Text("Optional. Match a bank’s full payee description to this payee and its default envelope when importing transactions.")
        }
        if let entry, entry.transactionCount == 0 && entry.scheduleCount == 0,
           entry.ruleID != nil {
          Section {
            Button("Delete Payee", role: .destructive) { showingDelete = true }
          }
        }
      }
      .navigationTitle(entry == nil ? "New Payee" : "Edit Payee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(trimmedName.isEmpty)
        }
      }
      .confirmationDialog("Delete this payee?", isPresented: $showingDelete) {
        Button("Delete Payee", role: .destructive) { delete() }
      } message: {
        Text("This removes the saved payee and its matching settings.")
      }
      .alert("Couldn’t Save Payee", isPresented: Binding(
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
    let newKey = PayeeDirectory.key(trimmedName)
    let allEntries = PayeeDirectory.entries(
      payees: payees, transactions: transactions, schedules: schedules
    )
    guard !allEntries.contains(where: { $0.key == newKey && $0.key != entry?.key }) else {
      errorMessage = "A payee with this name already exists."
      return
    }
    guard !payees.contains(where: {
      $0.id != entry?.ruleID && PayeeDirectory.key($0.exactMatchText) == newKey
    }) else {
      errorMessage = "This name is already used as another payee’s bank description."
      return
    }
    let exact = exactMatchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let exactKey = PayeeDirectory.key(exact)
    guard exact.isEmpty || !payees.contains(where: {
      $0.id != entry?.ruleID
        && (PayeeDirectory.key($0.exactMatchText) == exactKey
          || PayeeDirectory.key($0.name) == exactKey)
    }) else {
      errorMessage = "Another payee already matches this bank description."
      return
    }
    do {
      if let entry {
        let previousExact = payees.first { $0.id == entry.ruleID }?.exactMatchText ?? ""
        if newKey != entry.key || trimmedName != entry.name
            || PayeeDirectory.key(previousExact) != exactKey {
          PayeeDirectory.rename(
            from: entry.key,
            to: trimmedName,
            payees: payees,
            transactions: transactions,
            schedules: schedules
          )
        }
        if let payee = payees.first(where: { $0.id == entry.ruleID }) {
          payee.name = trimmedName
          payee.exactMatchText = exact
          payee.defaultEnvelopeID = defaultEnvelopeID
        } else {
          modelContext.insert(BudgetPayee(
            name: trimmedName,
            defaultEnvelopeID: defaultEnvelopeID,
            exactMatchText: exact
          ))
        }
      } else {
        modelContext.insert(BudgetPayee(
          name: trimmedName,
          defaultEnvelopeID: defaultEnvelopeID,
          exactMatchText: exact
        ))
      }
      try modelContext.save()
      dismiss()
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete() {
    guard let entry,
          entry.transactionCount == 0,
          entry.scheduleCount == 0,
          let payee = payees.first(where: { $0.id == entry.ruleID }) else { return }
    do {
      modelContext.delete(payee)
      try modelContext.save()
      dismiss()
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
