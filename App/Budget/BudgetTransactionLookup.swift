import Foundation
import SwiftData

enum BudgetTransactionLookup {
  static func byID(_ id: UUID, in context: ModelContext) throws -> BudgetTransaction? {
    var request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate { $0.id == id })
    request.fetchLimit = 1
    return try context.fetch(request).first
  }

  static func scheduled(
    scheduleID: UUID, on date: Date, excluding excludedID: UUID? = nil,
    in context: ModelContext
  ) throws -> BudgetTransaction? {
    let day = Calendar.current.startOfDay(for: date)
    let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    var request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.scheduleID == scheduleID && $0.scheduledFor != nil
        && $0.scheduledFor! >= day && $0.scheduledFor! < end
    })
    request.fetchLimit = 2
    return try context.fetch(request).first { $0.id != excludedID }
  }

  static func near(
    accountID: UUID, date: Date, days: Int,
    in context: ModelContext
  ) throws -> [BudgetTransaction] {
    let start = Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date.addingTimeInterval(-Double(days) * 86_400)
    let end = Calendar.current.date(byAdding: .day, value: days + 1, to: date) ?? date.addingTimeInterval(Double(days + 1) * 86_400)
    let request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.date >= start && $0.date < end
        && ($0.accountID == accountID || $0.transferAccountID == accountID)
    })
    return try context.fetch(request)
  }

  static func inEnvelope(_ id: UUID, in context: ModelContext) throws -> Bool {
    let request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate { $0.envelopeID == id })
    return try context.fetchCount(request) > 0
  }

  static func matchingPayee(_ name: String, in context: ModelContext) throws -> [BudgetTransaction] {
    try context.fetch(FetchDescriptor<BudgetTransaction>(predicate: #Predicate { $0.payee == name }))
  }
}
