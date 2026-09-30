import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var interfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .system: .unspecified
    case .light: .light
    case .dark: .dark
    }
  }
}
