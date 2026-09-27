import SwiftUI
import SwiftData

struct CategoryManagementScreen: View {
  @Query private var profiles: [BudgetProfile]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var editor: CategoryEditor?

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  private var orderedGroups: [BudgetGroup] {
    groups.sorted {
      $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
    }
  }

  var body: some View {
    List {
      if groups.isEmpty {
        ContentUnavailableView(
          "No groups yet",
          systemImage: "folder",
          description: Text("Add a group to organize your envelopes.")
        )
      }

      ForEach(orderedGroups) { group in
        Section {
          Button {
            editor = .editGroup(group)
          } label: {
            Label(group.name, systemImage: "folder")
              .fontWeight(.semibold)
          }
          .accessibilityHint("Edit group name")

          ForEach(envelopes
            .filter { $0.groupID == group.id }
            .sorted { $0.sortOrder == $1.sortOrder
              ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }) { envelope in
            Button {
              editor = .editEnvelope(envelope)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: envelope.symbol)
                  .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                  Text(envelope.name)
                  if let targetMinor = envelope.targetMinor {
                    Text("Target \(BudgetMoney.formatted(targetMinor, currencyCode: currencyCode))")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
            .accessibilityHint("Edit envelope and monthly target")
          }
        }
      }

      Section {
        Button("Add Group", systemImage: "folder.badge.plus") {
          editor = .newGroup
        }
        Button("Add Envelope", systemImage: "plus") {
          editor = .newEnvelope
        }
        .disabled(groups.isEmpty)
      }
    }
    .navigationTitle("Groups & Envelopes")
    .sheet(item: $editor) { selection in
      switch selection {
      case .newGroup:
        GroupEditorScreen(nextOrder: groups.count)
      case .editGroup(let group):
        GroupEditorScreen(nextOrder: groups.count, group: group)
      case .newEnvelope:
        EnvelopeEditorScreen(groups: groups, nextOrder: envelopes.count)
      case .editEnvelope(let envelope):
        EnvelopeEditorScreen(groups: groups, nextOrder: envelopes.count, envelope: envelope)
      }
    }
  }
}

private enum CategoryEditor: Identifiable {
  case newGroup
  case editGroup(BudgetGroup)
  case newEnvelope
  case editEnvelope(BudgetEnvelope)

  var id: String {
    switch self {
    case .newGroup: "newGroup"
    case .editGroup(let group): "group-\(group.id)"
    case .newEnvelope: "newEnvelope"
    case .editEnvelope(let envelope): "envelope-\(envelope.id)"
    }
  }
}
