import Foundation
import SwiftData

/// Keeps schedules up to date: notes each due date, then enters it on its date like a
/// transaction you entered yourself. Bills Bow can't enter on its own (no account, or an expense
/// without an envelope) wait in Spending for you to finish.
struct ScheduleReviewPlanner {
  var calendar: Calendar = .current

  func refresh(in context: ModelContext, today: Date = Date()) throws {
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let todayStart = calendar.startOfDay(for: today)
    let end = calendar.date(byAdding: .day, value: 1, to: todayStart)
      ?? todayStart.addingTimeInterval(86_400)
    let active = schedules.filter(\.isActive)
    try addDueDates(for: active, through: todayStart, end: end, in: context)
    try enterDueDates(for: active, before: end, in: context)
  }

  /// Notes each due date since the last check, so it can be entered or skipped.
  private func addDueDates(
    for active: [BudgetSchedule], through todayStart: Date, end: Date, in context: ModelContext
  ) throws {
    let recurrence = ScheduleRecurrence(calendar: calendar)
    let firstDays = active.map { schedule in
      schedule.reviewedThrough.flatMap {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
      } ?? todayStart
    }
    guard let earliest = firstDays.min(), earliest <= todayStart else { return }
    let occurrences = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>())
    let recordedKeys = try recordedKeys(from: earliest, before: end, in: context)
    var occurrenceKeys = Set(occurrences.map {
      ScheduleOccurrenceKey(scheduleID: $0.scheduleID, day: calendar.startOfDay(for: $0.scheduledFor))
    })
    for (schedule, firstDay) in zip(active, firstDays) {
      guard firstDay <= todayStart else { continue }
      var day = firstDay
      while day <= todayStart {
        let key = ScheduleOccurrenceKey(scheduleID: schedule.id, day: day)
        if recurrence.occurs(starting: schedule.startDate, frequency: schedule.frequency, on: day)
          && !occurrenceKeys.contains(key) && !recordedKeys.contains(key) {
          context.insert(BudgetScheduleOccurrence(scheduleID: schedule.id, scheduledFor: day))
          occurrenceKeys.insert(key)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
      schedule.reviewedThrough = todayStart
    }
    try context.save()
  }

  /// Enters every due date that isn't skipped or recorded yet, including ones left from before.
  private func enterDueDates(
    for active: [BudgetSchedule], before end: Date, in context: ModelContext
  ) throws {
    let scheduleByID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
    let due = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>(predicate: #Predicate {
      !$0.isSkipped && $0.scheduledFor < end
    })).filter { scheduleByID[$0.scheduleID] != nil }
    guard let earliest = due.map(\.scheduledFor).min() else { return }
    var recorded = try recordedKeys(from: calendar.startOfDay(for: earliest), before: end, in: context)
    let accounts = Dictionary(
      try context.fetch(FetchDescriptor<BudgetAccount>()).map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for occurrence in due.sorted(by: { $0.scheduledFor < $1.scheduledFor }) {
      guard let schedule = scheduleByID[occurrence.scheduleID] else { continue }
      let day = calendar.startOfDay(for: occurrence.scheduledFor)
      let key = ScheduleOccurrenceKey(scheduleID: schedule.id, day: day)
      guard !recorded.contains(key),
            let account = schedule.accountID.flatMap({ accounts[$0] }) else { continue }
      if try attachBankTransaction(for: schedule, on: day, account: account, in: context) {
        recorded.insert(key)
        continue
      }
      // Anything the budget won't accept as-is is left in Spending to finish by hand.
      if (try? BudgetCommands.addTransaction(
        kind: schedule.kind, account: account,
        destination: schedule.transferAccountID.flatMap { accounts[$0] },
        envelopeID: schedule.envelopeID, amountMinor: abs(schedule.amountMinor), date: day,
        payee: schedule.payee, notes: "",
        scheduleID: schedule.id, scheduledFor: day, in: context
      )) != nil {
        recorded.insert(key)
      }
    }
  }

  /// The bank got there first: one imported transaction with this bill's exact amount, within
  /// three days, becomes the bill's record, so entering it doesn't add a duplicate.
  private func attachBankTransaction(
    for schedule: BudgetSchedule, on day: Date, account: BudgetAccount, in context: ModelContext
  ) throws -> Bool {
    guard schedule.kind != .transfer else { return false }
    let signed = schedule.kind == .inflow ? abs(schedule.amountMinor) : -abs(schedule.amountMinor)
    let matches = try BudgetTransactionLookup.near(
      accountID: account.id, date: day, days: 3, in: context
    ).filter {
      ($0.sourceRaw == "simplefin" || $0.sourceRaw == "bankFile")
        && $0.accountID == account.id && $0.scheduleID == nil && $0.amountMinor == signed
    }
    guard matches.count == 1, let match = matches.first else { return false }
    match.scheduleID = schedule.id
    match.scheduledFor = day
    if match.envelopeID == nil { match.envelopeID = schedule.envelopeID }
    try context.save()
    return true
  }

  private func recordedKeys(
    from start: Date, before end: Date, in context: ModelContext
  ) throws -> Set<ScheduleOccurrenceKey> {
    var request = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.scheduleID != nil && $0.scheduledFor != nil
        && $0.scheduledFor! >= start && $0.scheduledFor! < end
    })
    request.propertiesToFetch = [\.id, \.scheduleID, \.scheduledFor]
    return Set(try context.fetch(request).compactMap { transaction -> ScheduleOccurrenceKey? in
      guard let scheduleID = transaction.scheduleID,
            let scheduledFor = transaction.scheduledFor else { return nil }
      return ScheduleOccurrenceKey(scheduleID: scheduleID, day: calendar.startOfDay(for: scheduledFor))
    })
  }
}

private struct ScheduleOccurrenceKey: Hashable {
  var scheduleID: UUID
  var day: Date
}
