import Foundation
import SwiftData

@Model
final class BudgetGroup {
  var id: UUID = UUID()
  var name: String = ""
  var sortOrder: Int = 0

  init(name: String, sortOrder: Int) {
    self.name = name
    self.sortOrder = sortOrder
  }
}
