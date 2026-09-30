import SwiftUI
import SwiftData

struct GroupEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var nextOrder: Int
  var group: BudgetGroup?
  @State private var name = ""
  @State private var errorMessage: String?
  @State private var showingDelete = false

  init(nextOrder: Int, group: BudgetGroup? = nil) {
    self.nextOrder = nextOrder
    self.group = group
    _name = State(initialValue: group?.name ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Group name") {
          TextField("For example, Food & Home", text: $name)
        }
        .listRowBackground(Bow.card)
        if group != nil {
          Section {
            Button("Delete group", role: .destructive) { showingDelete = true }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle(group == nil ? "New group" : "Edit group")
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
      .alert("Couldn’t save group", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .confirmationDialog("Delete this empty group?", isPresented: $showingDelete) {
        Button("Delete group", role: .destructive) {
          guard let group else { return }
          do {
            try BudgetCommands.deleteEmptyGroup(group, in: modelContext)
            dismiss()
          } catch { errorMessage = error.localizedDescription }
        }
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
