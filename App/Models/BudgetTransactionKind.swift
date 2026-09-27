import Foundation

enum BudgetTransactionKind: String, CaseIterable, Identifiable {
  case expense
  case inflow
  case transfer

  var id: String { rawValue }

  var title: String {
    switch self {
    case .expense: "Expense"
    case .inflow: "Inflow"
    case .transfer: "Transfer"
    }
  }
}
