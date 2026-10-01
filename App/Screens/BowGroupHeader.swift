import SwiftUI

/// A collapsible group's header, on Budget and Accounts: the group name, a trailing detail
/// ("4 envelopes", a group total) and a glass chevron that collapses or expands the group.
struct BowGroupHeader<Detail: View>: View {
  var name: String
  var isCollapsed: Bool
  var onToggle: () -> Void
  @ViewBuilder var detail: () -> Detail

  var body: some View {
    HStack(spacing: Bow.Space.s2) {
      HStack(spacing: Bow.Space.s2) {
        Text(name)
          .font(.bowHeadline)
          .foregroundStyle(Bow.inkSoft)
          .frame(maxWidth: .infinity, alignment: .leading)
        detail()
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

extension BowGroupHeader where Detail == Text {
  /// A Budget group: its name and how many envelopes it holds.
  init(name: String, count: Int, isCollapsed: Bool, onToggle: @escaping () -> Void) {
    self.init(name: name, isCollapsed: isCollapsed, onToggle: onToggle) {
      Text("^[\(count) envelope](inflect: true)")
    }
  }
}
