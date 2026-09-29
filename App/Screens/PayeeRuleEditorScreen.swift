import SwiftUI
import SwiftData

struct PayeeRuleEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var transactions: [BudgetTransaction]
  @Query private var schedules: [BudgetSchedule]
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
        Section("Default Envelope") {
          CategorySelectionField(title: "Category", selection: $envelopeID, envelopes: envelopes)
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
          PayeeDirectory.rename(
            from: PayeeDirectory.key(rule.name),
            to: updatedName,
            payees: rules,
            transactions: transactions,
            schedules: schedules
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
      PayeeDirectory.rename(
        from: PayeeDirectory.key(rule.name),
        to: rule.name,
        payees: rules,
        transactions: transactions,
        schedules: schedules
      )
      modelContext.delete(rule)
      try modelContext.save()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
