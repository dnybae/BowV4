import UIKit

/// Applies the chosen appearance to every window, so screens and any open sheets update together.
@MainActor
enum AppAppearanceController {
  static func apply(_ appearance: AppAppearance) {
    let style = appearance.interfaceStyle
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      for window in scene.windows where window.overrideUserInterfaceStyle != style {
        window.overrideUserInterfaceStyle = style
      }
    }
  }
}
