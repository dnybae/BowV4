import UIKit

@MainActor
enum AppIconAppearanceController {
  static func synchronize(for appearance: AppAppearance) {
    let application = UIApplication.shared
    guard application.supportsAlternateIcons else { return }

    let iconName = appearance.alternateIconName
    guard application.alternateIconName != iconName else { return }

    application.setAlternateIconName(iconName) { error in
      if let error {
        NSLog("Could not update Bow's app icon: %@", error.localizedDescription)
      }
    }
  }
}
