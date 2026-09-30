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
  @State private var isSaving = false

  init(rule: BudgetPayee?, rules: [BudgetPayee], envelopes: [BudgetEnvelope]) {
    self.rule = rule
    self.rules = rules
    self.envelopes = envelopes
    _name = State(initialValue: rule?.name ?? "")
    _matchText = State(initialValue: rule?.exactMatchText ?? "")
    _envelopeID = State(initialValue: rule?.defaultEnvelopeID ?? envelopes.first(where: { !$0.isHidden && $0.paymentAccountID == nil })?.id)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Payee") {
          TextField("Name", text: $name)
          TextField("Exact bank text (optional)", text: $matchText)
            .textInputAutocapitalization(.words)
        }
        .listRowBackground(Bow.card)
        Section("Default envelope") {
          CategorySelectionField(title: "Category", selection: $envelopeID, envelopes: envelopes)
        }
        .listRowBackground(Bow.card)
        if rule != nil {
          Section {
            Button("Delete Rule", role: .destructive) {
              showingDeleteConfirmation = true
            }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle(rule == nil ? "Add Payee Rule" : "Edit Payee Rule")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || envelopeID == nil || isSaving)
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

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    guard let envelopeID else { return }
    let matcher = PayeeRuleMatcher()
    let match = matcher.normalized(matchText)
    let normalizedName = matcher.normalized(name)
    guard match.isEmpty || !rules.contains(where: {
      $0.id != rule?.id
        && (matcher.normalized($0.exactMatchText) == match
          || matcher.normalized($0.name) == match)
    }) else {
      errorMessage = "Another rule already matches this payee text."
      return
    }
    guard rule == nil || !rules.contains(where: {
      $0.id != rule?.id
        && (matcher.normalized($0.name) == normalizedName
          || matcher.normalized($0.exactMatchText) == normalizedName)
    }) else {
      errorMessage = "Another payee already uses this name."
      return
    }
    do {
      if let rule {
        let updatedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.name != updatedName
            || matcher.normalized(rule.exactMatchText) != match {
          try await PayeeDirectoryRepository(modelContainer: modelContext.container)
            .renameHistory(
              from: Set([PayeeDirectory.key(rule.name),
                         PayeeDirectory.key(rule.exactMatchText)]).subtracting([""]),
              to: updatedName
            )
        }
        rule.name = updatedName
        rule.exactMatchText = matchText.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.defaultEnvelopeID = envelopeID
      } else {
        if let existing = rules.first(where: { matcher.normalized($0.name) == normalizedName }) {
          existing.defaultEnvelopeID = envelopeID
          existing.exactMatchText = matchText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
          modelContext.insert(BudgetPayee(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultEnvelopeID: envelopeID,
            exactMatchText: matchText.trimmingCharacters(in: .whitespacesAndNewlines)
          ))
        }
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
