import Foundation
import SwiftData

@Model
final class BudgetAccount {
  var id: UUID = UUID()
  var name: String = ""
  var kindRaw: String = BudgetAccountKind.cash.rawValue
  var currencyCode: String = "USD"
  var openingBalanceMinor: Int64 = 0
  var openedAt: Date = Date()
  var lastReconciledAt: Date? = nil
  var lastReconciledBalanceMinor: Int64? = nil

  var kind: BudgetAccountKind {
    BudgetAccountKind(rawValue: kindRaw) ?? .cash
  }

  init(name: String, kind: BudgetAccountKind, currencyCode: String, openingBalanceMinor: Int64) {
    self.name = name
    self.kindRaw = kind.rawValue
    self.currencyCode = currencyCode
    self.openingBalanceMinor = openingBalanceMinor
  }
}
