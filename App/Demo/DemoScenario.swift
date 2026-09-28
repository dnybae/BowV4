import Foundation

enum DemoScenario: String, CaseIterable, Identifiable {
  case showcase
  case empty
  case deficit

  var id: String { rawValue }

  var title: String {
    switch self {
    case .showcase: "Sample Budget"
    case .empty: "Empty Budget"
    case .deficit: "Cash Shortfall"
    }
  }

  var explanation: String {
    switch self {
    case .showcase: "Accounts, categories, schedules, imports, and bank review"
    case .empty: "First-use screens with no accounts or transactions"
    case .deficit: "A funded budget with negative Ready to Assign"
    }
  }
}
