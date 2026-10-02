import SwiftUI

/// Picks an envelope's group: the user's own groups, plus New Group… to make one on the spot.
/// Shows a grey "Choose a group" until one is picked.
struct EnvelopeGroupMenu: View {
  @Binding var selection: UUID?
  var groups: [BudgetGroup]
  var onNewGroup: () -> Void

  private var selectedName: String? {
    groups.first { $0.id == selection }?.name
  }

  var body: some View {
    Menu {
      Picker("Group", selection: $selection) {
        ForEach(groups) { group in
          Text(group.name).tag(Optional(group.id))
        }
      }
      .pickerStyle(.inline)
      Divider()
      Button("New Group…", systemImage: "plus", action: onNewGroup)
    } label: {
      HStack(spacing: 12) {
        BowFieldTitle(title: "Group", systemImage: "folder")
        Spacer(minLength: 12)
        Text(selectedName ?? "Choose a group")
          .foregroundStyle(selectedName == nil ? Bow.inkSoft : Bow.ink)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkFaint)
      }
      .contentShape(Rectangle())
    }
    .sensoryFeedback(.selection, trigger: selection)
    .accessibilityLabel("Group, \(selectedName ?? "Choose a group")")
  }
}
