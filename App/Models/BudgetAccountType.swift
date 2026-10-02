import Foundation

enum BudgetAccountType: String, CaseIterable, Identifiable {
  case checking
  case savings
  case cash
  case creditCard
  case loan
  case investment
  case other

  var id: String { rawValue }

  /// The order the type menu lists them in, on-budget first.
  static let onBudget: [BudgetAccountType] = [.checking, .savings, .cash, .creditCard]
  static let offBudget: [BudgetAccountType] = [.loan, .investment, .other]

  var title: String {
    switch self {
    case .checking: "Checking"
    case .savings: "Savings"
    case .cash: "Cash"
    case .creditCard: "Credit Card"
    case .loan: "Loan"
    case .investment: "Investment"
    case .other: "Other Asset"
    }
  }

  var kind: BudgetAccountKind {
    switch self {
    case .checking, .savings, .cash: .cash
    case .creditCard: .credit
    case .loan: .liability
    case .investment, .other: .asset
    }
  }

  /// Money owed: entered as a positive amount owed, stored as a negative balance.
  var isDebt: Bool { kind == .credit || kind == .liability }

  var systemImage: String {
    switch self {
    case .checking, .savings: kind.systemImage
    case .cash: "banknote.fill"
    case .creditCard: "creditcard.fill"
    case .loan: "percent"
    case .investment: "chart.line.uptrend.xyaxis"
    case .other: "shippingbox.fill"
    }
  }

  var explanation: String {
    switch self {
    case .checking, .savings, .cash: "On budget: money here is ready to assign to envelopes."
    case .creditCard: "On budget: card spending comes out of envelopes, and Bow sets money aside to pay the card."
    case .loan: "Off budget: tracked in net worth. Pay it from an envelope with a transfer."
    case .investment, .other: "Off budget: tracked in net worth, outside your spending budget."
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
