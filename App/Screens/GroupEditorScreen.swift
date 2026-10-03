import SwiftUI
import SwiftData

struct GroupEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var nextOrder: Int
  var group: BudgetGroup?
  /// Called with a newly added group, e.g. to select it in the envelope sheet that opened this one.
  var onAdded: ((BudgetGroup) -> Void)?
  @State private var name = ""
  @State private var errorMessage: String?
  @State private var showingDelete = false

  init(nextOrder: Int, group: BudgetGroup? = nil, onAdded: ((BudgetGroup) -> Void)? = nil) {
    self.nextOrder = nextOrder
    self.group = group
    self.onAdded = onAdded
    _name = State(initialValue: group?.name ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          BowNameHeader(placeholder: "For example, Food & Home", name: $name) {}
        } footer: {
          Group {
            Text("Groups hold related envelopes on the Budget screen, like bills or everyday spending.")
              .frame(maxWidth: .infinity)
              .multilineTextAlignment(.center)
          }
          .font(.bowFootnote)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        if group != nil {
          BowDestructiveSection("Delete group") { showingDelete = true }
        }
      }
      .bowListBackground()
      .bowEditorSheet(hasChanges: name != (group?.name ?? ""))
      .navigationTitle(group == nil ? "New group" : "Edit group")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: name != (group?.name ?? "")) { dismiss() }
        ToolbarItem(placement: .confirmationAction) {
          Button { save() } label: { BowToolbarLabel(group == nil ? "Add" : "Save") }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .bowErrorAlert("Couldn’t save group", message: $errorMessage)
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
        let added = try BudgetCommands.addGroup(name: name, order: nextOrder, in: modelContext)
        onAdded?(added)
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
