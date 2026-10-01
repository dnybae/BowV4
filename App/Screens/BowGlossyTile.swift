import SwiftUI

/// The white glossy rounded square behind identity blocks and context cards, holding an SF Symbol.
struct BowGlossyTile: View {
  var systemImage: String
  var size: CGFloat = 64
  @ScaledMetric private var scale: CGFloat = 1

  private var side: CGFloat { size * min(scale, Bow.maxGraphicScale) }

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: side * 0.42, weight: .medium))
      .foregroundStyle(Bow.inkSoft)
      .frame(width: side, height: side)
      .bowGlossyTileBackground(side: side)
      .accessibilityHidden(true)
  }
}

extension View {
  /// Glossy tile surface: white gradient, hairline highlight and a soft shadow (flat card in dark mode).
  func bowGlossyTileBackground(side: CGFloat) -> some View {
    modifier(BowGlossyTileBackground(radius: side * 0.3))
  }
}

private struct BowGlossyTileBackground: ViewModifier {
  var radius: CGFloat
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    content
      .clipShape(shape)
      .background {
        shape.fill(scheme == .dark
          ? AnyShapeStyle(Bow.card)
          : AnyShapeStyle(LinearGradient(colors: [.white, Color(red: 0.953, green: 0.961, blue: 0.980)],
                                         startPoint: .top, endPoint: .bottom)))
      }
      .overlay {
        shape.strokeBorder(.white.opacity(scheme == .dark ? 0.08 : 0.9), lineWidth: 1)
      }
      .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 10, y: 5)
  }
}
