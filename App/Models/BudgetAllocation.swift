import Foundation
import SwiftData

@Model
final class BudgetAllocation {
  #Index<BudgetAllocation>(
    [\.date, \.createdAt],
    [\.sourceEnvelopeID, \.date],
    [\.targetEnvelopeID, \.date],
    [\.sourceCardID, \.date],
    [\.targetCardID, \.date]
  )
  var id: UUID = UUID()
  var date: Date = Date()
  var createdAt: Date = Date()
  var amountMinor: Int64 = 0
  var sourceEnvelopeID: UUID? = nil
  var sourceCardID: UUID? = nil
  var targetEnvelopeID: UUID? = nil
  var targetCardID: UUID? = nil

  init(
    date: Date,
    amountMinor: Int64,
    sourceEnvelopeID: UUID? = nil,
    sourceCardID: UUID? = nil,
    targetEnvelopeID: UUID? = nil,
    targetCardID: UUID? = nil
  ) {
    self.date = date
    self.amountMinor = amountMinor
    self.sourceEnvelopeID = sourceEnvelopeID
    self.sourceCardID = sourceCardID
    self.targetEnvelopeID = targetEnvelopeID
    self.targetCardID = targetCardID
  }
}
