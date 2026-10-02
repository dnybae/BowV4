import Foundation
import SwiftData

/// The pre-launch audit's bugs, each reproduced and kept fixed.
@MainActor
@main
struct ReleaseRegressionChecks {
  static func main() throws {
    try futureMovesDoNotInflateReadyToAssign()
    try coveringFromReadyToAssignLowersIt()
    try bankDaysKeepTheirDate()
    try historyBeforeStartChangesNothing()
    try movingTheStartDateKeepsTheBalance()
    try balanceAdjustmentsNeverNeedAnEnvelope()
    try upgradeKeepsEveryBalance()
    try repeatMerchantsImportWithoutReview()
    goalTargetsSpreadWhatsLeft()
    futureMonthsOpenWithMoneyToPlan()
    try backupsRestoreExactly()
    print("Release regression checks passed")
  }

  // MARK: - Ready to Assign

  static func futureMovesDoNotInflateReadyToAssign() throws {
    let calculator = BudgetCalculator()
    let calendar = Calendar.current
    let thisMonth = calendar.dateInterval(of: .month, for: Date())!.start
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
    let monthAfter = calendar.date(byAdding: .month, value: 2, to: thisMonth)!
    let cashID = UUID(), groceriesID = UUID(), rentID = UUID()
    let cash = AccountLedgerItem(id: cashID, kind: .cash, openingBalanceMinor: 100_000, openedAt: thisMonth)
    let envelopes = [EnvelopeLedgerItem(id: groceriesID), EnvelopeLedgerItem(id: rentID)]
    func move(_ amount: Int64, _ from: BudgetBucket, _ to: BudgetBucket, on date: Date) -> AllocationLedgerItem {
      AllocationLedgerItem(id: UUID(), date: date, createdAt: date, amountMinor: amount, source: from, target: to)
    }
    let fundGroceries = move(30_000, .readyToAssign, .envelope(groceriesID), on: thisMonth)
    let giveBackNextMonth = move(30_000, .envelope(groceriesID), .readyToAssign, on: nextMonth)

    let now = calculator.calculate(month: thisMonth, accounts: [cash], envelopes: envelopes,
                                   allocations: [fundGroceries, giveBackNextMonth], transactions: [])
    expect(now.readyToAssignMinor == 70_000,
           "money a later month gives back is still in its envelope today")

    // A later month that gives money back can cover a draw after it, but not one before it.
    let drawThenReturn = [fundGroceries,
                          move(30_000, .readyToAssign, .envelope(rentID), on: nextMonth),
                          move(30_000, .envelope(groceriesID), .readyToAssign, on: monthAfter)]
    let reserved = calculator.calculate(month: thisMonth, accounts: [cash], envelopes: envelopes,
                                        allocations: drawThenReturn, transactions: [])
    expect(reserved.readyToAssignMinor == 40_000, "a draw before the give-back is reserved now")

    let returnThenDraw = [fundGroceries,
                          move(30_000, .envelope(groceriesID), .readyToAssign, on: nextMonth),
                          move(30_000, .readyToAssign, .envelope(rentID), on: monthAfter)]
    let covered = calculator.calculate(month: thisMonth, accounts: [cash], envelopes: envelopes,
                                       allocations: returnThenDraw, transactions: [])
    expect(covered.readyToAssignMinor == 70_000, "a give-back covers a later draw")
  }

  static func coveringFromReadyToAssignLowersIt() throws {
    let calculator = BudgetCalculator()
    let month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    let cashID = UUID(), groceriesID = UUID()
    let cash = AccountLedgerItem(id: cashID, kind: .cash, openingBalanceMinor: 10_000, openedAt: month)
    let spend = TransactionLedgerItem(id: UUID(), date: month, createdAt: month, amountMinor: -3_000,
                                      accountID: cashID, transferAccountID: nil, envelopeID: groceriesID,
                                      kind: .expense)
    let before = calculator.calculate(month: month, accounts: [cash], envelopes: [EnvelopeLedgerItem(id: groceriesID)],
                                      allocations: [], transactions: [spend])
    expect(before.readyToAssignMinor == 10_000 && before.available(for: groceriesID) == -3_000,
           "overspending shows on the envelope first")
    let cover = AllocationLedgerItem(id: UUID(), date: month, createdAt: month, amountMinor: 3_000,
                                     source: .readyToAssign, target: .envelope(groceriesID))
    let after = calculator.calculate(month: month, accounts: [cash], envelopes: [EnvelopeLedgerItem(id: groceriesID)],
                                     allocations: [cover], transactions: [spend])
    expect(after.readyToAssignMinor == 7_000 && after.available(for: groceriesID) == 0,
           "covering from Ready to Assign takes the money from Ready to Assign")
  }

  // MARK: - Calendar days

  static func bankDaysKeepTheirDate() throws {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let midnightUTC = utc.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let day = BowDay.fromBankTimestamp(midnightUTC.timeIntervalSince1970, calendar: newYork)
    let parts = newYork.dateComponents([.year, .month, .day, .hour], from: day)
    expect(parts.month == 10 && parts.day == 1 && parts.hour == 12,
           "a midnight-UTC posting stays on its date in New York")

    let afternoon = utc.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 2, minute: 30))!
    let realMoment = BowDay.fromBankTimestamp(afternoon.timeIntervalSince1970, calendar: newYork)
    expect(newYork.component(.day, from: realMoment) == 30,
           "a real timestamp is read on the local calendar")
  }

  // MARK: - Starting balances

  static func historyBeforeStartChangesNothing() throws {
    let context = try makeContext()
    let group = BudgetGroup(name: "Needs", sortOrder: 0)
    context.insert(group)
    let groceries = BudgetEnvelope(groupID: group.id, name: "Groceries", symbol: "", sortOrder: 0)
    context.insert(groceries)
    let today = Date()
    let checking = try BudgetCommands.addAccount(
      name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 100_000,
      startDate: today, in: context
    )
    let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
    let old = try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: nil,
      amountMinor: 2_500, date: lastWeek, payee: "Before Bow", notes: "", in: context
    )
    expect(old.isBeforeStart && !old.needsEnvelope, "history needs no envelope")
    expect(try balance(of: checking, in: context) == 100_000, "history is already in the starting balance")
    try BudgetCommands.deleteTransaction(old, in: context)
    expect(try balance(of: checking, in: context) == 100_000, "deleting history leaves the balance alone")

    let todayExpense = try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: groceries.id,
      amountMinor: 1_000, date: today, payee: "Market", notes: "", in: context
    )
    expect(!todayExpense.isBeforeStart, "the start day itself counts")
    expect(try balance(of: checking, in: context) == 99_000, "spending after the start changes the balance")
  }

  static func movingTheStartDateKeepsTheBalance() throws {
    let context = try makeContext()
    let group = BudgetGroup(name: "Needs", sortOrder: 0)
    context.insert(group)
    let groceries = BudgetEnvelope(groupID: group.id, name: "Groceries", symbol: "", sortOrder: 0)
    context.insert(groceries)
    let today = Date()
    let checking = try BudgetCommands.addAccount(
      name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 50_000,
      startDate: today, in: context
    )
    let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: today)!
    let old = try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: groceries.id,
      amountMinor: 4_000, date: tenDaysAgo, payee: "Market", notes: "", in: context
    )
    expect(old.isBeforeStart, "starts as history")
    try BudgetCommands.updateAccount(
      checking, name: "Checking", type: .checking, note: "",
      currentBalanceMinor: 50_000, existingBalanceMinor: 50_000,
      startDate: Calendar.current.date(byAdding: .day, value: -30, to: today)!, in: context
    )
    expect(!old.isBeforeStart, "an earlier start brings history into the ledger")
    expect(checking.openingBalanceMinor == 54_000, "the starting balance absorbs it")
    expect(try balance(of: checking, in: context) == 50_000, "today's balance is unchanged")
  }

  static func balanceAdjustmentsNeverNeedAnEnvelope() throws {
    let context = try makeContext()
    let card = try BudgetCommands.addAccount(
      name: "Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: 50_000, in: context
    )
    try BudgetCommands.updateAccount(
      card, name: "Card", type: .creditCard, note: "",
      currentBalanceMinor: -50_000, existingBalanceMinor: 50_000, in: context
    )
    let adjustments = try context.fetch(FetchDescriptor<BudgetTransaction>())
    expect(adjustments.count == 1 && adjustments[0].isBalanceAdjustment, "one adjustment is recorded")
    expect(!adjustments[0].needsEnvelope, "a balance adjustment never asks for an envelope")
    let inbox = ReviewInbox(transactions: adjustments, records: [], occurrences: [], schedules: [])
    expect(inbox.items.isEmpty, "and never waits in review")
  }

  static func upgradeKeepsEveryBalance() throws {
    let context = try makeContext()
    let profile = BudgetProfile(currencyCode: "USD")
    profile.dataVersion = 0
    context.insert(profile)
    let today = Date()
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 80_000)
    account.openedAt = today
    context.insert(account)
    // An earlier build counted pre-start bank items in the balance and moved the opening balance.
    let lastMonth = Calendar.current.date(byAdding: .day, value: -20, to: today)!
    let imported = BudgetTransaction(accountID: account.id, date: lastMonth, amountMinor: -5_000,
                                     payee: "Old", notes: "", kind: .expense)
    imported.sourceRaw = "simplefin"
    context.insert(imported)
    try context.save()
    let before = try balance(of: account, in: context)
    try BowDataUpgrade().run(in: context)
    expect(profile.dataVersion == BowDataUpgrade.currentVersion, "the upgrade is recorded in the budget")
    expect(imported.isBeforeStart, "pre-start items become history")
    expect(try balance(of: account, in: context) == before, "the upgrade keeps the balance")
  }

  // MARK: - Bank import

  static func repeatMerchantsImportWithoutReview() throws {
    let context = try makeContext()
    let today = Date()
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 10_000)
    account.openedAt = BowDay.start(of: Calendar.current.date(byAdding: .day, value: -30, to: today)!)
    context.insert(account)
    let group = BudgetGroup(name: "Everyday", sortOrder: 0)
    let food = BudgetEnvelope(groupID: group.id, name: "Food", symbol: "", sortOrder: 0)
    context.insert(group)
    context.insert(food)
    context.insert(BudgetPayee(name: "Groceries", defaultEnvelopeID: food.id, exactMatchText: "Groceries"))
    let link = SimpleFINAccountLink(remoteKey: "connection|bank-account", name: "Bank", currencyCode: "USD")
    link.localAccountID = account.id
    context.insert(link)
    try context.save()

    func sync(_ id: String, daysAgo: Int, amount: String) throws -> SimpleFINSyncSummary {
      let posted = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!.timeIntervalSince1970
      let remote = SimpleFINRemoteAccount(
        id: "bank-account", name: "Bank", connID: "connection", currency: "USD",
        transactions: [SimpleFINRemoteTransaction(id: id, posted: posted, amount: amount,
                                                  description: "Groceries", transactedAt: nil, pending: false)]
      )
      let summary = try SimpleFINSyncCoordinator.shared.importTransactions([remote], in: context)
      try context.save()
      return summary
    }
    let first = try sync("g1", daysAgo: 4, amount: "-12.75")
    expect(first.imported == 1, "the first purchase imports")
    let second = try sync("g2", daysAgo: 2, amount: "-9.10")
    expect(second.imported == 1 && second.needsReview == 0,
           "a second purchase at the same store isn't held as a possible duplicate")
  }

  // MARK: - Targets and months

  static func goalTargetsSpreadWhatsLeft() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let planner = EnvelopeTargetPlanner(calendar: calendar)
    let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let march = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
    expect(planner.monthsLeft(from: october, through: march) == 6, "October through March is six months")
    expect(planner.monthlyMinor(targetMinor: 120_000, targetDate: march, scheduledMinor: 0,
                                carriedInMinor: 0, month: october) == 20_000,
           "a goal is spread over the months left")
    expect(planner.monthlyMinor(targetMinor: 120_000, targetDate: march, scheduledMinor: 0,
                                carriedInMinor: 60_000, month: october) == 10_000,
           "money already saved lowers the monthly amount")
    expect(planner.monthlyMinor(targetMinor: 120_000, targetDate: march, scheduledMinor: 0,
                                carriedInMinor: 130_000, month: october) == nil,
           "a reached goal asks for nothing")
    expect(planner.monthlyMinor(targetMinor: 5_000, targetDate: nil, scheduledMinor: 1_000,
                                carriedInMinor: 0, month: october) == 6_000,
           "a monthly target adds to scheduled bills")
  }

  static func futureMonthsOpenWithMoneyToPlan() {
    let policy = BudgetMonthAccessPolicy()
    let today = Date()
    expect(policy.canAdvance(from: today, today: today, assignedMinor: 0, readyToAssignMinor: 5_000),
           "money waiting in Ready to Assign opens the next month")
    expect(!policy.canAdvance(from: today, today: today, assignedMinor: 0, readyToAssignMinor: 0),
           "with nothing to plan, the next month stays closed")
    let farAhead = Calendar.current.date(byAdding: .month, value: 12, to: today)!
    expect(!policy.canAdvance(from: farAhead, today: today, assignedMinor: 5_000, readyToAssignMinor: 5_000),
           "planning stops a year out")
  }

  // MARK: - Backup

  static func backupsRestoreExactly() throws {
    let source = try makeContext()
    try BudgetCommands.createBudget(currencyCode: "USD", withDefaults: true, in: source)
    let checking = try BudgetCommands.addAccount(
      name: "Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 250_000, in: source
    )
    _ = try BudgetCommands.addAccount(
      name: "Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: -40_000, in: source
    )
    let groceries = try source.fetch(FetchDescriptor<BudgetEnvelope>()).first { $0.name == "Groceries" }!
    try BudgetCommands.addTransaction(
      kind: .expense, account: checking, destination: nil, envelopeID: groceries.id,
      amountMinor: 4_321, date: Date(), payee: "Market, \"Downtown\"", notes: "=SUM(A1)", in: source
    )
    let data = try BowBackup.make(from: source, appVersion: "1.0").encoded()

    let target = try makeContext()
    try BudgetCommands.createBudget(currencyCode: "USD", withDefaults: false, in: target)
    try BowBackup.decode(data).restore(into: target)

    expect(try target.fetch(FetchDescriptor<BudgetProfile>()).count == 1, "one budget after restoring")
    expect(try target.fetch(FetchDescriptor<BudgetEnvelope>()).count
           == (try source.fetch(FetchDescriptor<BudgetEnvelope>()).count), "every envelope comes back")
    let restoredChecking = try target.fetch(FetchDescriptor<BudgetAccount>()).first { $0.id == checking.id }!
    expect(try balance(of: restoredChecking, in: target) == 245_679, "balances match after restoring")
    let restored = try target.fetch(FetchDescriptor<BudgetTransaction>()).first!
    expect(restored.envelopeID == groceries.id && restored.payee == "Market, \"Downtown\"",
           "transactions keep their envelope and text")

    let csv = try TransactionCSVExporter().csv(from: target)
    expect(csv.contains("\"Market, \"\"Downtown\"\"\""), "CSV quotes commas and quotes")
    expect(csv.contains("'=SUM(A1)"), "CSV never exports a live formula")
  }

  // MARK: - Helpers

  static func makeContext() throws -> ModelContext {
    let schema = Schema(BowSchemaV1.models)
    let container = try ModelContainer(
      for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
  }

  static func balance(of account: BudgetAccount, in context: ModelContext) throws -> Int64 {
    let report = BudgetLedger.accountBalanceReport(
      before: Date().addingTimeInterval(86_400), accounts: try context.fetch(FetchDescriptor<BudgetAccount>()),
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>())
    )
    return report.balances[account.id, default: 0]
  }

  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
