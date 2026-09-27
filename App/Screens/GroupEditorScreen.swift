import SwiftUI
import SwiftData

struct GroupEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var nextOrder: Int
  @State private var name = ""
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Group Name") {
          TextField("For example, Food & Home", text: $name)
        }
      }
      .navigationTitle("Add Group")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("Couldn’t Add Group", isPresented: Binding(
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
      try BudgetCommands.addGroup(name: name, order: nextOrder, in: modelContext)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
