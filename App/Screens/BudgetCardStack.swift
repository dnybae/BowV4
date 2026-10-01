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
  @ViewBuilder var row: (Item) -> Row

  private static var cardRadius: CGFloat { 22 }
  /// Each sliver sits this much lower than the card in front of it.
  private static var sliverDrop: CGFloat { 10 }

  private var visibleItems: [Item] { isCollapsed ? Array(items.prefix(1)) : items }
  private var sliverCount: Int { isCollapsed ? min(items.count - 1, 2) : 0 }

  var body: some View {
    VStack(spacing: Bow.Space.s2) {
      ForEach(visibleItems) { item in
        Button { onOpen(route(item)) } label: {
          card { row(item) }
        }
        .buttonStyle(BudgetCardButtonStyle())
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
    .overlay {
      if isCollapsed {
        Button(action: onExpand) {
          Color.clear.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(groupName), ^[\(items.count) envelope](inflect: true), collapsed"))
        .accessibilityHint("Expands the group")
      }
    }
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: Bow.Space.s3) {
      content()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Bow.inkFaint)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Bow.Space.s4)
    .frame(maxWidth: .infinity, minHeight: 68)
    .contentShape(.rect(cornerRadius: Self.cardRadius))
    .bowCard(radius: Self.cardRadius)
  }

  /// A narrower card edge peeking out below the front card: 12pt inset per level, 10pt lower.
  private func sliver(depth: Int) -> some View {
    RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
      .fill(Bow.card.opacity(depth == 1 ? 0.85 : 0.7))
      .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
      .padding(.horizontal, CGFloat(depth) * 12)
      .offset(y: CGFloat(depth) * Self.sliverDrop)
      .accessibilityHidden(true)
  }
}

/// Envelope cards dim slightly while pressed.
private struct BudgetCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .bowAnimation(value: configuration.isPressed)
  }
}
