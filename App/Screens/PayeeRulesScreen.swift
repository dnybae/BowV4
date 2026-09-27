import SwiftUI
import SwiftData

struct PayeeRulesScreen: View {
  @Query private var rules: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var showingAdd = false
  @State private var editingRule: BudgetPayee?

  var body: some View {
    List {
      if rules.isEmpty {
        ContentUnavailableView(
          "No payee rules yet",
          systemImage: "person.text.rectangle",
          description: Text("Match a payee name to an envelope for faster categorization.")
        )
      } else {
        ForEach(rules.sorted { $0.name < $1.name }) { rule in
          Button {
            editingRule = rule
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(rule.name)
                .foregroundStyle(.primary)
              Text("\(rule.exactMatchText) → \(envelopes.first { $0.id == rule.defaultEnvelopeID }?.name ?? "Choose an envelope")")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Section {
        Button("Add Payee Rule", systemImage: "plus") {
          showingAdd = true
        }
        .disabled(envelopes.isEmpty)
      } footer: {
        Text("Rules match the full payee text, ignoring case and surrounding spaces. They never change an envelope you selected yourself.")
      }
    }
    .navigationTitle("Payee Rules")
    .sheet(isPresented: $showingAdd) {
      PayeeRuleEditorScreen(rule: nil, rules: rules, envelopes: envelopes)
    }
    .sheet(item: $editingRule) { rule in
      PayeeRuleEditorScreen(rule: rule, rules: rules, envelopes: envelopes)
    }
  }
}
