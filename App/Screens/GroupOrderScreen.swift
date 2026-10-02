import SwiftUI
import SwiftData

/// Native reordering for groups, separate from dragging envelopes between their groups.
struct GroupOrderScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var groups: [BudgetGroup]
  @State private var message: String?

  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted {
      $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if #available(iOS 27.0, *) {
          List {
            ForEach(orderedGroups) { group in
              Text(group.name).font(.bowHeadline).listRowBackground(Bow.card)
            }
            .reorderable()
          }
          .reorderContainer(for: BudgetGroup.self) { difference in
            let moving = orderedGroups.filter { difference.sources.contains($0.id) }
            var ordered = orderedGroups.filter { !difference.sources.contains($0.id) }
            let destination: Int
            switch difference.destination.position {
            case .before(let id): destination = ordered.firstIndex { $0.id == id } ?? ordered.count
            case .end: destination = ordered.count
            }
            ordered.insert(contentsOf: moving, at: destination)
            save(ordered)
          }
        } else {
          List {
            ForEach(orderedGroups) { group in
              Text(group.name).font(.bowHeadline).listRowBackground(Bow.card)
            }
            .onMove { offsets, destination in
              var ordered = orderedGroups
              ordered.move(fromOffsets: offsets, toOffset: destination)
              save(ordered)
            }
          }
          .environment(\.editMode, .constant(.active))
        }
      }
      .bowListBackground()
      .navigationTitle("Reorder groups")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Done", systemImage: "checkmark") }
        }
      }
      .bowErrorAlert("Couldn’t reorder groups", message: $message)
    }
  }

  private func save(_ ordered: [BudgetGroup]) {
    let previous = ordered.map { ($0, $0.sortOrder) }
    for (index, group) in ordered.enumerated() { group.sortOrder = index }
    do { try modelContext.save() } catch {
      for (group, order) in previous { group.sortOrder = order }
      message = error.localizedDescription
    }
  }
}
