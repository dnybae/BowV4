import SwiftUI

/// One of the equal-width buttons under the envelope ring: a symbol over a short label.
/// The main action is prominent (dark ink fill); the others are glass.
struct BowActionTile: View {
  var title: String
  var systemImage: String
  var isProminent = false
  var action: () -> Void
  @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 22

  init(_ title: String, systemImage: String, isProminent: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.isProminent = isProminent
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: Bow.Space.s1) {
        Image(systemName: systemImage)
          .font(.system(size: iconSize, weight: .semibold))
          .accessibilityHidden(true)
        Text(title)
          .font(.bowSubhead.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, minHeight: 68)
      .padding(.horizontal, Bow.Space.s2)
      .contentShape(.rect(cornerRadius: BowActionTileStyle.radius))
    }
    .buttonStyle(BowActionTileStyle(isProminent: isProminent))
  }
}

/// Lays out action tiles in an equal-width row, stacking them at accessibility text sizes.
struct BowActionTileRow<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Bow.Space.s3))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s3))
    layout { content() }
  }
}

private struct BowActionTileStyle: ButtonStyle {
  static let radius: CGFloat = 20
  var isProminent: Bool
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let label = configuration.label
      .foregroundStyle(isProminent ? Bow.onButton : Bow.bowInk)
      .opacity(isEnabled ? 1 : 0.45)
    Group {
      if isProminent {
        label.background(Bow.button, in: .rect(cornerRadius: Self.radius))
      } else {
        label.bowGlassCard(radius: Self.radius)
      }
    }
    .scaleEffect(configuration.isPressed ? 0.96 : 1)
    .bowAnimation(value: configuration.isPressed)
  }
}
