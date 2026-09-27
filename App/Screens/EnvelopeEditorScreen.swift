import SwiftUI
import SwiftData

struct EnvelopeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var groups: [BudgetGroup]
  var nextOrder: Int
  @State private var name = ""
  @State private var groupID: UUID?
  @State private var symbol = "square.grid.2x2.fill"
  @State private var errorMessage: String?

  private var symbols: [String] {
    [
      "cart.fill", "house.fill", "bolt.fill", "fork.knife",
      "car.fill", "wrench.adjustable.fill", "bag.fill", "heart.fill",
      "sparkles", "cross.case.fill", "banknote.fill", "square.grid.2x2.fill"
    ]
  }

  init(groups: [BudgetGroup], nextOrder: Int) {
    self.groups = groups
    self.nextOrder = nextOrder
    _groupID = State(initialValue: groups.first?.id)
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
        Section("Symbol") {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(symbols, id: \.self) { option in
              Button {
                symbol = option
              } label: {
                Image(systemName: option)
                  .font(.title3)
                  .frame(maxWidth: .infinity, minHeight: 42)
                  .foregroundStyle(symbol == option ? Color.white : Color.accentColor)
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
      .navigationTitle("Add Envelope")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groupID == nil)
        }
      }
      .alert("Couldn’t Add Envelope", isPresented: Binding(
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
      try BudgetCommands.addEnvelope(
        name: name,
        symbol: symbol,
        groupID: groupID,
        order: nextOrder,
        in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
