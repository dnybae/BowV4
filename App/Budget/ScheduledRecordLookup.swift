import Foundation
import SwiftData

struct ScheduledRecordLookup {
  func transactions(
    for occurrences: [BudgetScheduleOccurrence], in context: ModelContext
  ) throws -> [BudgetTransaction] {
    guard let earliest = occurrences.map(\.scheduledFor).min(),
          let latest = occurrences.map(\.scheduledFor).max() else { return [] }
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: earliest)
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest))
      ?? latest.addingTimeInterval(86_400)
    let predicate = #Predicate<BudgetTransaction> { transaction in
      transaction.scheduledFor != nil
        && transaction.scheduledFor! >= start
        && transaction.scheduledFor! < end
    }
    return try context.fetch(FetchDescriptor(predicate: predicate))
  }
}
