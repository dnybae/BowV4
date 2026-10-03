import Foundation
import SwiftData

@MainActor
@main
struct TransactionSchedulingChecks {
  static func main() throws {
    try creationUsesDateAndRecurrence()
    try editingDoesNotDuplicateTheInitialTransaction()
    try invalidPlansSaveNothing()
    try resumeDoesNotBackfill()
    try directoryKeepsEveryScheduleReachable()
    nextDatesKeepTheirAnchor()
    print("Transaction scheduling checks passed")
  }

  static func creationUsesDateAndRecurrence() throws {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    for offset in [-28, 0, 35] {
      for recurring in [false, true] {
        let (container, account, envelope) = try fixture()
        let context = container.mainContext
        let selected = calendar.date(byAdding: .day, value: offset, to: today)!
        let timing = TransactionTiming(date: selected, isRecurring: recurring, frequency: .weekly, now: today)
        let schedule = try TransactionScheduling.save(
          kind: .expense, account: account, destination: nil, envelopeID: envelope.id,
          amountMinor: 1200, payee: "Gym", notes: "Membership", timing: timing, in: context
        )
        try ScheduleReviewPlanner().refresh(in: context, today: today)
        try ScheduleReviewPlanner().refresh(in: context, today: today)
        let transactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
        precondition(transactions.count == (offset > 0 ? 0 : 1),
                     "Only the selected past/today occurrence is recorded; future and missed dates are not")
        precondition((schedule != nil) == (recurring || offset > 0))
        if let schedule {
          precondition(schedule.frequency == (recurring ? .weekly : .once))
          precondition(schedule.reviewedThrough == today)
          let upcoming = UpcomingSchedules().items(for: [schedule], skipped: [], after: today)
          precondition(upcoming.count == 1 && upcoming[0].date > today)
          precondition(transactions.first?.scheduleID == schedule.id || transactions.isEmpty)
        }
        let balances = BudgetLedger.accountBalanceReport(
          before: calendar.date(byAdding: .day, value: 1, to: today)!, accounts: [account], transactions: transactions
        )
        precondition(balances.balances[account.id] == 10_000 - (offset > 0 ? 0 : 1200),
                     "Future plans must not change current balances")
      }
    }
  }

  static func editingDoesNotDuplicateTheInitialTransaction() throws {
    let (container, account, envelope) = try fixture()
    let context = container.mainContext
    let calendar = Calendar.current
    let oldDate = calendar.date(byAdding: .day, value: -28, to: Date())!
    let transaction = try BudgetCommands.addTransaction(
      kind: .expense, account: account, destination: nil, envelopeID: envelope.id,
      amountMinor: 900, date: oldDate, payee: "Gym", notes: "", in: context
    )
    let schedule = try TransactionScheduling.save(
      transaction: transaction, kind: .expense, account: account, destination: nil,
      envelopeID: envelope.id, amountMinor: 1200, payee: "Gym", notes: "",
      timing: TransactionTiming(date: oldDate, isRecurring: true, frequency: .weekly), in: context
    )!
    try ScheduleReviewPlanner().refresh(in: context)
    try expect(context.fetchCount(FetchDescriptor<BudgetTransaction>()) == 1)
    precondition(transaction.amountMinor == -1200 && transaction.scheduleID == schedule.id)

    let manual = try BudgetCommands.addTransaction(
      kind: .inflow, account: account, destination: nil, envelopeID: nil,
      amountMinor: 500, date: Date(), payee: "Deposit", notes: "", in: context
    )
    let future = calendar.date(byAdding: .day, value: 10, to: Date())!
    let manualID = manual.id
    let converted = try TransactionScheduling.save(
      transaction: manual, kind: .inflow, account: account, destination: nil,
      envelopeID: nil, amountMinor: 500, payee: "Deposit", notes: "",
      timing: TransactionTiming(date: future, isRecurring: false, frequency: .monthly), in: context
    )!
    precondition(converted.frequency == .once)
    try expect(BudgetTransactionLookup.byID(manualID, in: context) == nil)
    try expect(context.fetchCount(FetchDescriptor<BudgetTransaction>()) == 1)
  }

  static func invalidPlansSaveNothing() throws {
    let (container, account, envelope) = try fixture()
    let context = container.mainContext
    let future = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
    do {
      try TransactionScheduling.save(
        kind: .expense, account: account, destination: nil, envelopeID: nil,
        amountMinor: 1200, payee: "Gym", notes: "",
        timing: TransactionTiming(date: future, isRecurring: true, frequency: .weekly), in: context
      )
      preconditionFailure("Expenses must have an envelope before they can recur")
    } catch BudgetCommandError.expenseNeedsEnvelope { }
    try expect(context.fetchCount(FetchDescriptor<BudgetSchedule>()) == 0)

    let confirmed = try BudgetCommands.addTransaction(
      kind: .expense, account: account, destination: nil, envelopeID: envelope.id,
      amountMinor: 1200, date: Date(), payee: "Gym", notes: "", in: context
    )
    confirmed.isCleared = true
    try context.save()
    do {
      try TransactionScheduling.save(
        transaction: confirmed, kind: .expense, account: account, destination: nil,
        envelopeID: envelope.id, amountMinor: 1200, payee: "Gym", notes: "",
        timing: TransactionTiming(date: future, isRecurring: false, frequency: .monthly), in: context
      )
      preconditionFailure("Confirmed transactions must keep their recorded history")
    } catch { }
    try expect(context.fetchCount(FetchDescriptor<BudgetSchedule>()) == 0)
    try expect(context.fetchCount(FetchDescriptor<BudgetTransaction>()) == 1)
  }

  static func resumeDoesNotBackfill() throws {
    let (container, account, envelope) = try fixture()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let start = calendar.date(byAdding: .day, value: -28, to: today)!
    let schedule = BudgetSchedule(payee: "Gym", amountMinor: 1200, accountID: account.id,
      envelopeID: envelope.id, startDate: start, frequency: .weekly, notes: "")
    schedule.isActive = false
    schedule.reviewedThrough = start
    context.insert(schedule)
    let missed = BudgetScheduleOccurrence(scheduleID: schedule.id,
      scheduledFor: calendar.date(byAdding: .day, value: -7, to: today)!)
    context.insert(missed)
    try context.save()
    try ScheduleManagement.setActive(true, for: schedule, in: context, now: today)
    try ScheduleReviewPlanner().refresh(in: context, today: today)
    try expect(context.fetchCount(FetchDescriptor<BudgetTransaction>()) == 0,
                 "Resuming must not enter paused dates or today’s missed occurrence")
    try expect(context.fetchCount(FetchDescriptor<BudgetScheduleOccurrence>()) == 0)
    precondition(UpcomingSchedules().items(for: [schedule], skipped: [], after: today).first?.date
      == calendar.date(byAdding: .day, value: 7, to: today))
  }

  static func directoryKeepsEveryScheduleReachable() throws {
    let (container, account, envelope) = try fixture()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    func schedule(_ name: String, date: Date, frequency: ScheduleFrequency) -> BudgetSchedule {
      BudgetSchedule(payee: name, amountMinor: 1200, accountID: account.id,
        envelopeID: envelope.id, startDate: date, frequency: frequency, notes: "")
    }
    let farDate = calendar.date(byAdding: .year, value: 3, to: today)!
    let far = schedule("Far future", date: farDate, frequency: .once)
    let repeatBill = schedule("Repeat", date: today, frequency: .monthly)
    let paused = schedule("Paused", date: today, frequency: .yearly)
    paused.isActive = false
    let complete = schedule("Complete", date: today, frequency: .once)
    let due = schedule("Due", date: today, frequency: .once)
    let skipped = BudgetScheduleOccurrence(scheduleID: repeatBill.id,
      scheduledFor: ScheduleRecurrence().nextDate(starting: today, frequency: .monthly,
        onOrAfter: calendar.date(byAdding: .day, value: 1, to: today)!)!)
    skipped.isSkipped = true
    let occurrence = BudgetScheduleOccurrence(scheduleID: due.id, scheduledFor: today)
    let recorded: Set<ScheduleDateKey> = [.init(scheduleID: complete.id, date: today)]
    let items = ScheduleDirectory().items(schedules: [far, repeatBill, paused, complete, due],
      occurrences: [skipped, occurrence], recorded: recorded, now: today)
    precondition(items.count == 4 && items.first?.id == due.id && items.last?.id == paused.id)
    precondition(items.first?.needsAttention == true)
    precondition(items.first { $0.id == far.id }?.date == farDate,
                 "Schedules beyond a year must remain reachable")
    precondition(items.first { $0.id == repeatBill.id }?.date != skipped.scheduledFor)
    precondition(UpcomingSchedules().items(for: [far], skipped: [], after: today).first?.date == farDate)

    // The directory must read actual recorded keys, including normalized transaction days.
    context.insert(complete)
    try context.save()
    try BudgetCommands.addTransaction(kind: .expense, account: account, destination: nil,
      envelopeID: envelope.id, amountMinor: 1200, date: today, payee: "Complete", notes: "",
      scheduleID: complete.id, scheduledFor: today, in: context)
    try expect(ScheduleDirectory().recordedDates(in: context).contains(.init(scheduleID: complete.id, date: today)))
  }

  static func nextDatesKeepTheirAnchor() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    let recurrence = ScheduleRecurrence(calendar: calendar)
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    precondition(recurrence.nextDate(starting: day(2026, 1, 31), frequency: .monthly,
      onOrAfter: day(2026, 2, 1)) == day(2026, 2, 28))
    precondition(recurrence.nextDate(starting: day(2026, 1, 31), frequency: .monthly,
      onOrAfter: day(2026, 3, 1)) == day(2026, 3, 31))
    precondition(recurrence.nextDate(starting: day(2024, 2, 29), frequency: .yearly,
      onOrAfter: day(2027, 3, 1)) == day(2028, 2, 29))
    precondition(recurrence.nextDate(starting: day(2026, 3, 1), frequency: .weekly,
      onOrAfter: day(2026, 3, 8)) == day(2026, 3, 8))
    precondition(recurrence.nextDate(starting: day(2026, 1, 1), frequency: .once,
      onOrAfter: day(2026, 1, 2)) == nil)
  }

  static func expect(_ condition: Bool, _ message: String = "") {
    precondition(condition, message)
  }

  static func fixture() throws -> (ModelContainer, BudgetAccount, BudgetEnvelope) {
    let schema = Schema(BowSchemaV1.models)
    let container = try ModelContainer(for: schema,
      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    let context = container.mainContext
    let group = BudgetGroup(name: "Needs", sortOrder: 0)
    let envelope = BudgetEnvelope(groupID: group.id, name: "Health", symbol: "", sortOrder: 0)
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000)
    account.openedAt = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
    context.insert(account)
    context.insert(group)
    context.insert(envelope)
    try context.save()
    return (container, account, envelope)
  }
}
