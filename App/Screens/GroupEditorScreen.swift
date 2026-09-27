import SwiftUI
import SwiftData

struct GroupEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var nextOrder: Int
  var group: BudgetGroup?
  @State private var name = ""
  @State private var errorMessage: String?

  init(nextOrder: Int, group: BudgetGroup? = nil) {
    self.nextOrder = nextOrder
    self.group = group
    _name = State(initialValue: group?.name ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Group Name") {
          TextField("For example, Food & Home", text: $name)
        }
      }
      .navigationTitle(group == nil ? "Add Group" : "Edit Group")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(group == nil ? "Add" : "Save") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("Couldn’t Save Group", isPresented: Binding(
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
    do {
      if let group {
        group.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try modelContext.save()
      } else {
        try BudgetCommands.addGroup(name: name, order: nextOrder, in: modelContext)
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
