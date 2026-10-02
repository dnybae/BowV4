import SwiftUI

extension View {
  /// Keeps text on one line and, when it's wider than the space it's given, fades out its
  /// trailing end instead of showing an ellipsis. Takes no more width than the text needs, so
  /// give the view that should win the space (usually the amount) a higher `layoutPriority`.
  func fadingTail(fadeWidth: CGFloat = 24) -> some View {
    modifier(FadingTail(fadeWidth: fadeWidth))
  }
}

private struct FadingTail: ViewModifier {
  var fadeWidth: CGFloat
  @State private var fullWidth: CGFloat = 0
  @State private var shownWidth: CGFloat = 0

  private var isCut: Bool { fullWidth > shownWidth + 0.5 }

  func body(content: Content) -> some View {
    FadingTailLayout {
      content
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shownWidth = $0 }
    .mask {
      if isCut, shownWidth > 0 {
        LinearGradient(
          stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: max(0, 1 - fadeWidth / shownWidth)),
            .init(color: .clear, location: 1)
          ],
          startPoint: .leading, endPoint: .trailing
        )
      } else {
        Rectangle()
      }
    }
  }
}

/// Sizes to the smaller of the offered width and the child's natural width, and always lays the
/// child out at its natural width from the leading edge, so anything past the edge is masked away.
private struct FadingTailLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let child = subviews.first else { return .zero }
    let natural = child.sizeThatFits(.unspecified)
    return CGSize(width: min(proposal.width ?? natural.width, natural.width), height: natural.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
  }

  /// Passes the child's text baselines through so it still lines up in baseline-aligned stacks.
  func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                         subviews: Subviews, cache: inout ()) -> CGFloat? {
    guard let child = subviews.first else { return nil }
    return bounds.minY + child.dimensions(in: .unspecified)[guide]
  }
}
