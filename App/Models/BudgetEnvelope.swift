import Foundation
import SwiftData

@Model
final class BudgetEnvelope {
  #Index<BudgetEnvelope>([\.groupID, \.sortOrder])
  var id: UUID = UUID()
  var groupID: UUID = UUID()
  var name: String = ""
  var symbol: String = "square.grid.2x2.fill"
  var sortOrder: Int = 0
  var targetMinor: Int64? = nil
  var targetDate: Date? = nil
  /// Derived by ScheduleTargetSynchronizer: what scheduled bills add to the target in `scheduledTargetMonth`.
  var scheduledTargetMinor: Int64 = 0
  var scheduledTargetMonth: Date? = nil
  var isHidden: Bool = false
  var paymentAccountID: UUID? = nil

  /// The user's own target plus scheduled bills for the current month.
  var totalMonthlyTargetMinor: Int64? {
    let total = (targetMinor ?? 0) + scheduledTargetMinor
    return total > 0 ? total : nil
  }

  init(groupID: UUID, name: String, symbol: String, sortOrder: Int) {
    self.groupID = groupID
    self.name = name
    self.symbol = symbol
    self.sortOrder = sortOrder
  }
}
