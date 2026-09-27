import Foundation
import SwiftData

@Model
final class BudgetProfile {
  var id: UUID = UUID()
  var currencyCode: String = "USD"
  var createdAt: Date = Date()

  init(currencyCode: String) {
    self.currencyCode = currencyCode
  }
}
