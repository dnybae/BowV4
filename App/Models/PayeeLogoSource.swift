import Foundation

enum PayeeLogoSource: String {
  case system
  case logoDev
  case custom

  var title: String {
    switch self {
    case .system: "Default Icon"
    case .logoDev: "Logo.dev"
    case .custom: "Your Image"
    }
  }
}
