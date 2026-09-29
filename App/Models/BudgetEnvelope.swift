import Foundation
import SwiftData

@Model
final class BudgetEnvelope {
  var id: UUID = UUID()
  var groupID: UUID = UUID()
  var name: String = ""
  var symbol: String = "square.grid.2x2.fill"
  var sortOrder: Int = 0
  var targetMinor: Int64? = nil
  var targetDate: Date? = nil
  var isHidden: Bool = false
  var paymentAccountID: UUID? = nil

  init(groupID: UUID, name: String, symbol: String, sortOrder: Int) {
    self.groupID = groupID
    self.name = name
    self.symbol = symbol
    self.sortOrder = sortOrder
  }
}
