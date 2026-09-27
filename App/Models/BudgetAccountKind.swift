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
    case .cash: "banknote.fill"
    case .credit: "creditcard.fill"
    case .asset: "chart.bar.fill"
    case .liability: "arrow.down.left"
    }
  }

  var isOnBudgetCash: Bool { self == .cash }
}
