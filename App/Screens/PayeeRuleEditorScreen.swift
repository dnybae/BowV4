import SwiftUI
import SwiftData

struct PayeeRuleEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var rule: BudgetPayee?
  var rules: [BudgetPayee]
  var envelopes: [BudgetEnvelope]
  @State private var name: String
  @State private var matchText: String
  @State private var envelopeID: UUID?
  @State private var errorMessage: String?
  @State private var showingDeleteConfirmation = false

  init(rule: BudgetPayee?, rules: [BudgetPayee], envelopes: [BudgetEnvelope]) {
    self.rule = rule
    self.rules = rules
    self.envelopes = envelopes
    _name = State(initialValue: rule?.name ?? "")
    _matchText = State(initialValue: rule?.exactMatchText ?? "")
    _envelopeID = State(initialValue: rule?.defaultEnvelopeID ?? envelopes.first?.id)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Payee") {
          TextField("Name", text: $name)
          TextField("Exact text to match", text: $matchText)
            .textInputAutocapitalization(.words)
        }
        Section("Default Envelope") {
          Picker("Envelope", selection: $envelopeID) {
            ForEach(envelopes.sorted { $0.name < $1.name }) { envelope in
              Text(envelope.name).tag(Optional(envelope.id))
            }
          }
        }
        if rule != nil {
          Section {
            Button("Delete Rule", role: .destructive) {
              showingDeleteConfirmation = true
            }
          }
        }
      }
      .navigationTitle(rule == nil ? "Add Payee Rule" : "Edit Payee Rule")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || matchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || envelopeID == nil)
        }
      }
      .confirmationDialog("Delete this rule?", isPresented: $showingDeleteConfirmation) {
        Button("Delete Rule", role: .destructive) { delete() }
      } message: {
        Text("Existing transactions keep their categories.")
      }
      .alert("Couldn’t Save Rule", isPresented: Binding(
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
    guard let envelopeID else { return }
    let matcher = PayeeRuleMatcher()
    let match = matcher.normalized(matchText)
    guard !rules.contains(where: {
      $0.id != rule?.id && matcher.normalized($0.exactMatchText) == match
    }) else {
      errorMessage = "Another rule already matches this payee text."
      return
    }
    do {
      if let rule {
        rule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.exactMatchText = matchText.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.defaultEnvelopeID = envelopeID
      } else {
        modelContext.insert(BudgetPayee(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines),
          defaultEnvelopeID: envelopeID,
          exactMatchText: matchText.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
      }
      try modelContext.save()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete() {
    guard let rule else { return }
    do {
      modelContext.delete(rule)
      try modelContext.save()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
