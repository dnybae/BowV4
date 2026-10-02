import Foundation
import SwiftData

@Model
final class BudgetProfile {
  var id: UUID = UUID()
  var currencyCode: String = "USD"
  var name: String = "My Budget"
  var createdAt: Date = Date()
  var bundledPayeesVersion: Int = 0
  /// The last `BowDataUpgrade` step this budget's data has been through.
  var dataVersion: Int = 0

  init(currencyCode: String) {
    self.currencyCode = currencyCode
    // A new budget starts with data in the current shape.
    self.dataVersion = BowDataUpgrade.currentVersion
  }
}
