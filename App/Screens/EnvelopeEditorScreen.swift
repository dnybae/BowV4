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
  @State private var symbol = "square.grid.2x2.fill"
  @State private var targetText = ""
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

  private var symbols: [String] {
    [
      "cart.fill", "house.fill", "bolt.fill", "fork.knife",
      "car.fill", "wrench.adjustable.fill", "bag.fill", "heart.fill",
      "sparkles", "cross.case.fill", "banknote.fill", "square.grid.2x2.fill"
    ]
  }

  init(groups: [BudgetGroup], nextOrder: Int, envelope: BudgetEnvelope? = nil) {
    self.groups = groups
    self.nextOrder = nextOrder
    self.envelope = envelope
    _name = State(initialValue: envelope?.name ?? "")
    _groupID = State(initialValue: envelope?.groupID ?? groups.first?.id)
    _symbol = State(initialValue: envelope?.symbol ?? "square.grid.2x2.fill")
    _targetText = State(initialValue: envelope?.targetMinor.map(BudgetMoney.editable) ?? "")
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
        } footer: {
          Text("Optional planning goal. A target does not assign money to this envelope.")
        }
        Section("Symbol") {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(symbols, id: \.self) { option in
              Button {
                symbol = option
              } label: {
                Image(systemName: option)
                  .font(.title3)
                  .frame(maxWidth: .infinity, minHeight: 42)
                  .foregroundStyle(symbol == option
                    ? Color(uiColor: .systemBackground) : Color.accentColor)
                  .background(
                    symbol == option ? Color.accentColor : Color.accentColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                  )
              }
              .buttonStyle(.plain)
              .accessibilityLabel(option.replacingOccurrences(of: ".", with: " "))
              .accessibilityAddTraits(symbol == option ? .isSelected : [])
            }
          }
          .padding(.vertical, 6)
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
    do {
      if let envelope {
        envelope.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        envelope.groupID = groupID
        envelope.symbol = symbol
        envelope.targetMinor = targetMinor
        try modelContext.save()
      } else {
        try BudgetCommands.addEnvelope(
          name: name,
          symbol: symbol,
          groupID: groupID,
          order: nextOrder,
          targetMinor: targetMinor,
          in: modelContext
        )
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
