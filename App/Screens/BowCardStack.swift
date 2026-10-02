import SwiftUI

/// A group's items as separate rounded cards, on Budget and Accounts. When collapsed, the cards
/// slide up behind the first one and stack like iOS notifications: up to two narrower slivers
/// peek below, and tapping the stack expands the group. Every card stays in the layout, so
/// collapsing and expanding moves the real cards rather than fading them in place.
struct BowCardStack<Item: Identifiable, Card: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var items: [Item]
  var isCollapsed: Bool
  /// What VoiceOver reads for the collapsed stack, e.g. "Bills, 4 envelopes, collapsed".
  var collapsedLabel: Text
  var onExpand: () -> Void
  /// One tappable card: a button or link around a `BowItemCard`.
  @ViewBuilder var card: (Item) -> Card
  @State private var isStackPressed = false

  /// Each sliver sits this much lower than the card in front of it.
  private static var sliverDrop: CGFloat { 10 }
  /// How many slivers peek out below the front card.
  private static var maxDepth: Int { 2 }

  var body: some View {
    CardStackLayout(
      isCollapsed: isCollapsed, spacing: Bow.Space.s2,
      sliverDrop: Self.sliverDrop, maxDepth: Self.maxDepth
    ) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        stackedCard(item, index: index)
      }
    }
    // A collapsed stack presses as one object, slivers and all.
    .bowPressEffect(isPressed: isCollapsed && isStackPressed)
    .overlay {
      if isCollapsed {
        Button(action: onExpand) {
          Color.clear.contentShape(.rect)
        }
        .buttonStyle(PressReportingStyle(isPressed: $isStackPressed))
        .accessibilityLabel(collapsedLabel)
        .accessibilityHint("Expands the group")
      }
    }
    // Reduce Motion: cross-fade between the two states instead of sliding the cards.
    .id(reduceMotion ? AnyHashable(isCollapsed) : AnyHashable(0))
    .transition(.opacity)
  }

  /// A card that, when tucked behind the front card, fades its content into a blank sliver
  /// and shrinks toward its bottom edge so the edge stays visible below the card in front.
  private func stackedCard(_ item: Item, index: Int) -> some View {
    let depth = min(index, Self.maxDepth)
    let isTucked = isCollapsed && index > 0
    return card(item)
      .opacity(isTucked ? 0 : 1)
      .background {
        sliver(depth: depth)
          .opacity(isTucked && index <= Self.maxDepth ? 1 : 0)
      }
      .scaleEffect(isTucked ? 1 - CGFloat(depth) * 0.06 : 1, anchor: .bottom)
      .zIndex(Double(items.count - index))
      .allowsHitTesting(!isCollapsed)
      .accessibilityHidden(isCollapsed)
  }

  private func sliver(depth: Int) -> some View {
    RoundedRectangle(cornerRadius: Bow.itemCardRadius, style: .continuous)
      .fill(Bow.card.opacity(depth == 1 ? 0.85 : 0.7))
      .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
      .accessibilityHidden(true)
  }
}

/// Lays cards out in a column, or, when collapsed, piles them behind the first card with each
/// one's bottom edge a little lower than the card in front. Animating `isCollapsed` slides
/// every card between the two arrangements.
private struct CardStackLayout: Layout {
  var isCollapsed: Bool
  var spacing: CGFloat
  var sliverDrop: CGFloat
  var maxDepth: Int

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.replacingUnspecifiedDimensions().width
    let heights = cardHeights(subviews, width: width)
    guard let first = heights.first else { return .zero }
    if isCollapsed {
      return CGSize(width: width, height: first + CGFloat(min(heights.count - 1, maxDepth)) * sliverDrop)
    }
    return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let heights = cardHeights(subviews, width: bounds.width)
    guard let first = heights.first else { return }
    var y = bounds.minY
    for (index, subview) in subviews.enumerated() {
      let height = heights[index]
      if isCollapsed {
        let depth = CGFloat(min(index, maxDepth))
        y = max(bounds.minY, bounds.minY + first + depth * sliverDrop - height)
      }
      subview.place(
        at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: height)
      )
      if !isCollapsed { y += height + spacing }
    }
  }

  private func cardHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
    subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
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
