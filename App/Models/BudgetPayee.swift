import Foundation
import SwiftData

@Model
final class BudgetPayee {
  var id: UUID = UUID()
  var name: String = ""
  var defaultEnvelopeID: UUID? = nil
  var exactMatchText: String = ""

  init(name: String, defaultEnvelopeID: UUID? = nil, exactMatchText: String = "") {
    self.name = name
    self.defaultEnvelopeID = defaultEnvelopeID
    self.exactMatchText = exactMatchText
  }
}
