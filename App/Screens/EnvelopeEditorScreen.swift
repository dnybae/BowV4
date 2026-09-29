import SwiftUI
import SwiftData

struct EnvelopeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var groups: [BudgetGroup]
  var nextOrder: Int
  var envelope: BudgetEnvelope?
  @State private var name = ""
  @State private var groupID: UUID?
  @State private var targetText = ""
  @State private var hasTargetDate = false
  @State private var targetDate = Date()
  @State private var errorMessage: String?

  private var targetMinor: Int64? {
    let trimmed = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return BudgetMoney.parseMinor(trimmed)
  }

  private var targetIsValid: Bool {
    targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || (targetMinor ?? 0) > 0
  }

  init(groups: [BudgetGroup], nextOrder: Int, envelope: BudgetEnvelope? = nil) {
    self.groups = groups
    self.nextOrder = nextOrder
    self.envelope = envelope
    _name = State(initialValue: envelope?.name ?? "")
    _groupID = State(initialValue: envelope?.groupID ?? groups.first?.id)
    _targetText = State(initialValue: envelope?.targetMinor.map(BudgetMoney.editable) ?? "")
    _hasTargetDate = State(initialValue: envelope?.targetDate != nil)
    _targetDate = State(initialValue: envelope?.targetDate ?? Date())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Envelope") {
          TextField("Name", text: $name)
          Picker("Group", selection: $groupID) {
            ForEach(groups) { group in
              Text(group.name).tag(Optional(group.id))
            }
          }
        }
        Section {
          TextField("Monthly Target", text: $targetText)
            .keyboardType(.decimalPad)
          Toggle("Set target date", isOn: $hasTargetDate)
          if hasTargetDate {
            DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
          }
        } footer: {
          Text("Optional planning goal. A target does not assign money to this envelope.")
        }
      }
      .navigationTitle(envelope == nil ? "Add Envelope" : "Edit Envelope")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(envelope == nil ? "Add" : "Save") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || groupID == nil || !targetIsValid)
        }
      }
      .alert("Couldn’t Save Envelope", isPresented: Binding(
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
    guard let groupID else { return }
    guard groups.contains(where: { $0.id == groupID && !$0.isSystem }) else {
      errorMessage = "Choose a regular envelope group."
      return
    }
    do {
      if let envelope {
        envelope.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        envelope.groupID = groupID
        envelope.targetMinor = targetMinor
        envelope.targetDate = hasTargetDate ? targetDate : nil
        try modelContext.save()
      } else {
        try BudgetCommands.addEnvelope(
          name: name,
          symbol: "",
          groupID: groupID,
          order: nextOrder,
          targetMinor: targetMinor,
          targetDate: hasTargetDate ? targetDate : nil,
          in: modelContext
        )
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
