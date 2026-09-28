import Foundation

enum ReviewEntry: Identifiable {
  case transaction(BudgetTransaction)
  case bankRecord(SimpleFINImportRecord, relatedOccurrence: BudgetScheduleOccurrence?)
  case scheduled(BudgetScheduleOccurrence, BudgetSchedule)

  var id: String {
    switch self {
    case .transaction(let item): "transaction-\(item.id)"
    case .bankRecord(let item, _): "bank-\(item.id)"
    case .scheduled(let item, _): "scheduled-\(item.id)"
    }
  }

  var date: Date {
    switch self {
    case .transaction(let item): item.date
    case .bankRecord(let item, _): item.date
    case .scheduled(let item, _): item.scheduledFor
    }
  }
}

struct ReviewInbox {
  var items: [ReviewEntry]

  init(
    transactions: [BudgetTransaction],
    records: [SimpleFINImportRecord],
    occurrences: [BudgetScheduleOccurrence],
    schedules: [BudgetSchedule],
    calendar: Calendar = .current
  ) {
    var result = transactions.filter(\.needsApproval).map(ReviewEntry.transaction)
    let scheduleByID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
    let pending = occurrences.filter { occurrence in
      guard !occurrence.isSkipped, scheduleByID[occurrence.scheduleID] != nil else { return false }
      return !transactions.contains {
        $0.scheduleID == occurrence.scheduleID
          && $0.scheduledFor.map {
            calendar.isDate($0, inSameDayAs: occurrence.scheduledFor)
          } == true
      }
    }
    let unresolved = records.filter { $0.status == .review }
    var groupedOccurrenceIDs = Set<UUID>()
    for record in unresolved {
      let related = pending.first { occurrence in
        guard let schedule = scheduleByID[occurrence.scheduleID] else { return false }
        return schedule.accountID == record.localAccountID
          && record.amountMinor == -schedule.amountMinor
          && calendar.isDate(record.date, inSameDayAs: occurrence.scheduledFor)
          && schedule.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(record.payee.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
      }
      if let related { groupedOccurrenceIDs.insert(related.id) }
      result.append(.bankRecord(record, relatedOccurrence: related))
    }
    result.append(contentsOf: pending.compactMap { occurrence in
      guard !groupedOccurrenceIDs.contains(occurrence.id),
            let schedule = scheduleByID[occurrence.scheduleID] else { return nil }
      return .scheduled(occurrence, schedule)
    })
    items = result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
  }
}
