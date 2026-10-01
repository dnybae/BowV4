import SwiftUI

/// A Budget group's section header: the group name, "N envelopes" and a glass chevron
/// that collapses or expands the group.
struct BudgetGroupHeader: View {
  var name: String
  var count: Int
  var isCollapsed: Bool
  var onToggle: () -> Void

  var body: some View {
    HStack(spacing: Bow.Space.s2) {
      HStack(spacing: Bow.Space.s2) {
        Text(name)
          .font(.bowHeadline)
          .foregroundStyle(Bow.inkSoft)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("^[\(count) envelope](inflect: true)")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      .contentShape(.rect)
      .onTapGesture(perform: onToggle)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)

      Button(action: onToggle) {
        Label {
          Text(isCollapsed ? "Expand \(name)" : "Collapse \(name)")
        } icon: {
          Image(systemName: "chevron.right")
            .font(.bowFootnote.weight(.semibold))
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 28, minHeight: 28)
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
      // The glass circle stays small; the tap area meets the 44pt minimum.
      .contentShape(.rect.inset(by: -Bow.Space.s2))
      .foregroundStyle(Bow.inkSoft)
      .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }
    .textCase(nil)
  }
}
