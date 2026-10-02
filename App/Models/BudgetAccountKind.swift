import Foundation

enum BudgetAccountKind: String, CaseIterable, Identifiable {
  case cash
  case credit
  case asset
  case liability

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cash: "Cash"
    case .credit: "Credit Card"
    case .asset: "Asset"
    case .liability: "Liability"
    }
  }

  var systemImage: String {
    switch self {
    case .cash:
      if #available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *) {
        "building.classical.columns.fill"
      } else {
        "building.columns.fill"
      }
    case .credit: "creditcard.fill"
    case .asset: "chart.bar.fill"
    case .liability: "arrow.down.left"
    }
  }

  var isOnBudgetCash: Bool { self == .cash }
}
