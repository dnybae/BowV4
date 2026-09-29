import Foundation
import SwiftData

@Model
final class BudgetSchedule {
  var id: UUID = UUID()
  var payee: String = ""
  var amountMinor: Int64 = 0
  var accountID: UUID? = nil
  var transferAccountID: UUID? = nil
  var envelopeID: UUID? = nil
  var kindRaw: String = BudgetTransactionKind.expense.rawValue
  var startDate: Date = Date()
  var frequencyRaw: String = ScheduleFrequency.monthly.rawValue
  var notes: String = ""
  var isActive: Bool = true
  var reviewedThrough: Date? = nil

  var frequency: ScheduleFrequency {
    ScheduleFrequency(rawValue: frequencyRaw) ?? .monthly
  }

  var kind: BudgetTransactionKind {
    BudgetTransactionKind(rawValue: kindRaw) ?? .expense
  }

  init(payee: String, amountMinor: Int64, accountID: UUID?, envelopeID: UUID?, startDate: Date, frequency: ScheduleFrequency, notes: String,
       kind: BudgetTransactionKind = .expense, transferAccountID: UUID? = nil) {
    self.payee = payee
    self.amountMinor = amountMinor
    self.accountID = accountID
    self.envelopeID = envelopeID
    self.kindRaw = kind.rawValue
    self.transferAccountID = transferAccountID
    self.startDate = startDate
    self.frequencyRaw = frequency.rawValue
    self.notes = notes
    self.reviewedThrough = Calendar.current.date(byAdding: .day, value: -1, to: Date())
  }
}
