import Foundation

enum TransactionIconSymbol {
  static func name(
    for kind: BudgetTransactionKind?, payee: String, category: String?
  ) -> String {
    if kind == .transfer { return "arrow.left.arrow.right" }
    if kind == .inflow {
      let label = payee.localizedLowercase
      return containsAny(label, ["paycheck", "payroll", "salary", "wages", "direct deposit"])
        ? "banknote.fill" : "arrow.down.left"
    }

    let label = "\(category ?? "") \(payee)".localizedLowercase
    if containsAny(label, ["dining", "restaurant", "coffee", "takeout", "cafe", "starbucks", "dunkin"]) {
      return "fork.knife"
    }
    if containsAny(label, ["grocer", "supermarket", "whole foods", "trader joe", "kroger", "aldi", "instacart", "costco"]) {
      return "cart.fill"
    }
    if containsAny(label, ["rent", "housing", "mortgage", "home"]) { return "house.fill" }
    if containsAny(label, ["utilit", "electric", "internet", "phone bill"]) { return "bolt.fill" }
    if containsAny(label, ["transport", "fuel", "gas", "car ", "auto"]) { return "car.fill" }
    if containsAny(label, ["medical", "health", "pharmacy", "dental"]) { return "cross.case.fill" }
    if containsAny(label, ["travel", "flight", "hotel"]) { return "airplane" }
    if containsAny(label, ["gift", "shopping", "clothing", "target", "walmart", "amazon"]) {
      return "bag.fill"
    }
    return "storefront.fill"
  }

  private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
    keywords.contains(where: text.contains)
  }
}
