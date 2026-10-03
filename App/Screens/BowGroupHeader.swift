import SwiftUI

/// A collapsible group's header, on Budget and Accounts: the group name, a trailing detail
/// ("4 envelopes", a group total) and a chevron that collapses or expands the group.
struct BowGroupHeader<Detail: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var name: String
  var isCollapsed: Bool
  var onToggle: () -> Void
  @ViewBuilder var detail: () -> Detail

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s1))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s2))
    Button(action: onToggle) {
      HStack(spacing: Bow.Space.s2) {
        layout {
          Text(name)
            .font(.bowHeadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          detail()
            .font(.bowSubhead)
        }
        Image(systemName: "chevron.right")
          .font(.bowFootnote.weight(.semibold))
          .rotationEffect(.degrees(isCollapsed ? 0 : 90))
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Bow.inkSoft)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    .accessibilityHint(isCollapsed ? "Expands the group" : "Collapses the group")
    .textCase(nil)
  }
}

extension BowGroupHeader where Detail == Text {
  /// A Budget group: its name and how many envelopes it holds.
  init(name: String, count: Int, isCollapsed: Bool, onToggle: @escaping () -> Void) {
    self.init(name: name, isCollapsed: isCollapsed, onToggle: onToggle) {
      isCollapsed ? Text("") : Text("^[\(count) envelope](inflect: true)")
    }
  }
}
