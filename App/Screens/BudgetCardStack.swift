import SwiftUI

/// A Budget group's rows as separate rounded cards. When collapsed, it stacks like iOS
/// notifications: the first card stays visible with up to two narrower slivers peeking below,
/// and tapping the stack expands the group. Place it in one List row with a clear background.
struct BudgetCardStack<Item: Identifiable, Row: View>: View {
  var groupName: String
  var items: [Item]
  var isCollapsed: Bool
  var onExpand: () -> Void
  var route: (Item) -> BudgetRoute
  /// Opens a card's route. Cards use buttons, not NavigationLinks: several links in one List row
  /// make the List treat the whole row as one link, so taps open the wrong (or several) envelopes.
  var onOpen: (BudgetRoute) -> Void
  /// Cards become zoom sources for the detail screen they open.
  var zoomNamespace: Namespace.ID
  @ViewBuilder var row: (Item) -> Row
  @State private var isStackPressed = false

  /// Each sliver sits this much lower than the card in front of it.
  private static var sliverDrop: CGFloat { 10 }

  private var visibleItems: [Item] { isCollapsed ? Array(items.prefix(1)) : items }
  private var sliverCount: Int { isCollapsed ? min(items.count - 1, 2) : 0 }

  var body: some View {
    VStack(spacing: Bow.Space.s2) {
      ForEach(visibleItems) { item in
        Button { onOpen(route(item)) } label: {
          BowItemCard { row(item) }
        }
        .buttonStyle(.bowPress)
        .matchedTransitionSource(id: route(item), in: zoomNamespace)
        .allowsHitTesting(!isCollapsed)
        .accessibilityHidden(isCollapsed)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
      }
    }
    .background(alignment: .top) {
      ZStack(alignment: .top) {
        // Back to front: the narrowest, lowest sliver first.
        ForEach(Array(stride(from: sliverCount, to: 0, by: -1)), id: \.self) { depth in
          sliver(depth: depth)
        }
      }
    }
    .padding(.bottom, CGFloat(sliverCount) * Self.sliverDrop)
    // A collapsed stack presses as one object, slivers and all.
    .bowPressEffect(isPressed: isCollapsed && isStackPressed)
    .overlay {
      if isCollapsed {
        Button(action: onExpand) {
          Color.clear.contentShape(.rect)
        }
        .buttonStyle(PressReportingStyle(isPressed: $isStackPressed))
        .accessibilityLabel(Text("\(groupName), ^[\(items.count) envelope](inflect: true), collapsed"))
        .accessibilityHint("Expands the group")
      }
    }
  }

  /// A narrower card edge peeking out below the front card: 12pt inset per level, 10pt lower.
  private func sliver(depth: Int) -> some View {
    RoundedRectangle(cornerRadius: Bow.itemCardRadius, style: .continuous)
      .fill(Bow.card.opacity(depth == 1 ? 0.85 : 0.7))
      .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
      .padding(.horizontal, CGFloat(depth) * Bow.Space.s3)
      .offset(y: CGFloat(depth) * Self.sliverDrop)
      .accessibilityHidden(true)
  }
}

/// Reports the press state outward, so a transparent hit area can press the view beneath it.
private struct PressReportingStyle: ButtonStyle {
  @Binding var isPressed: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
  }
}
