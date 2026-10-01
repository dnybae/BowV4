import SwiftUI

/// The house press for standalone cards and tiles: a slight scale, no fade.
/// Driven by `isPressed`, so it springs back when a scroll or drag takes the touch away.
/// Not for List rows (they keep the native highlight) or native glass buttons.
struct BowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .bowPressEffect(isPressed: configuration.isPressed)
  }
}

/// The press for rows that share one card outside a List: a soft highlight over the row,
/// like a List row, so tinted rows keep their color.
struct BowRowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay {
        if configuration.isPressed {
          Bow.pressOverlay.allowsHitTesting(false)
        }
      }
      .bowAnimation(value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == BowPressStyle {
  static var bowPress: BowPressStyle { BowPressStyle() }
}

extension ButtonStyle where Self == BowRowPressStyle {
  static var bowRowPress: BowRowPressStyle { BowRowPressStyle() }
}

extension View {
  /// The press scale shared by every Bow card and tile style.
  func bowPressEffect(isPressed: Bool) -> some View {
    scaleEffect(isPressed ? Bow.pressScale : 1)
      .bowAnimation(value: isPressed)
  }
}
