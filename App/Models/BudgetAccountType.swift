import Foundation

enum BudgetAccountType: String, CaseIterable, Identifiable {
  case checking
  case savings
  case creditCard
  case loan
  case investment
  case other

  var id: String { rawValue }

  var title: String {
    switch self {
    case .checking: "Checking"
    case .savings: "Savings"
    case .creditCard: "Credit Card"
    case .loan: "Loan"
    case .investment: "Investment"
    case .other: "Other"
    }
  }

  var kind: BudgetAccountKind {
    switch self {
    case .checking, .savings: .cash
    case .creditCard: .credit
    case .loan: .liability
    case .investment, .other: .asset
    }
  }

  var explanation: String {
    switch self {
    case .checking, .savings: "Money in this account is available to assign in your budget."
    case .creditCard: "Credit card balances are tracked in your budget. Enter money owed as a negative balance."
    case .loan: "Loans are tracked in net worth, outside your spending budget. Enter money owed as a negative balance."
    case .investment, .other: "This account is tracked in net worth, outside your spending budget."
    }
  }

  static func defaultType(for kind: BudgetAccountKind) -> BudgetAccountType {
    switch kind {
    case .cash: .checking
    case .credit: .creditCard
    case .asset: .investment
    case .liability: .loan
    }
  }
}
