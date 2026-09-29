import Foundation
import SwiftData

/// Builds month checkpoints with short-lived contexts. No persistent model or
/// full-history transaction array crosses to the main actor.
@ModelActor
actor BudgetSnapshotRepository {
  private var snapshots: [Date: BudgetSnapshot] = [:]
  private var checkpoints: [Date: BudgetCalculator.Checkpoint] = [:]
  private var balanceReports: [Date: AccountBalanceReport] = [:]
  private var accounts: [AccountLedgerItem] = []
  private var envelopes: [EnvelopeLedgerItem] = []
  private var allocations: [AllocationLedgerItem] = []
  private var firstMonth: Date?

  func invalidate() {
    snapshots.removeAll()
    checkpoints.removeAll()
    balanceReports.removeAll()
    accounts.removeAll()
    envelopes.removeAll()
    allocations.removeAll()
    firstMonth = nil
  }

  func snapshot(month: Date) throws -> BudgetSnapshot {
    let requested = monthStart(month)
    try ensureSnapshots(through: requested)
    guard let result = snapshots[requested] else { throw BudgetReadError.missingSnapshot }
    return result
  }

  func accountReport(at date: Date, currencyCode: String) throws -> AccountBalanceReport {
    try prepareStaticData()
    let current = monthStart(date)
    let previous = Calendar.current.date(byAdding: .month, value: -1, to: current)
    if let previous, firstMonth.map({ previous >= $0 }) == true {
      try ensureSnapshots(through: previous)
    }
    let prior = previous.flatMap { balanceReports[$0] }
    let adjustedAccounts = accounts.map { account -> AccountLedgerItem in
      var adjusted = account
      if let balance = prior?.balances[account.id] { adjusted.openingBalanceMinor = balance }
      return adjusted
    }
    let items = try transactions(from: current, through: date)
    return report(
      before: date, inclusive: true, accounts: adjustedAccounts,
      transactions: items, previous: prior, currencyCode: currencyCode
    )
  }

  func bundle(month: Date, currencyCode: String) throws -> BudgetReadBundle {
    let current = monthStart(month)
    try ensureSnapshots(through: current)
    let previous = Calendar.current.date(byAdding: .month, value: -1, to: current)
    let report = try accountReport(at: Date(), currencyCode: currencyCode)
    guard let result = snapshots[current] else { throw BudgetReadError.missingSnapshot }
    return BudgetReadBundle(
      current: result,
      previous: previous.flatMap { snapshots[$0] },
      accountReport: report
    )
  }

  private func prepareStaticData() throws {
    guard firstMonth == nil else { return }
    let context = ModelContext(modelContainer)
    accounts = try context.fetch(FetchDescriptor<BudgetAccount>()).map {
      AccountLedgerItem(
        id: $0.id, kind: $0.kind, openingBalanceMinor: $0.openingBalanceMinor,
        openedAt: $0.openedAt, currencyCode: $0.currencyCode
      )
    }
    envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>()).map {
      EnvelopeLedgerItem(id: $0.id, paymentAccountID: $0.paymentAccountID)
    }
    allocations = try context.fetch(FetchDescriptor<BudgetAllocation>()).compactMap { item in
      let target: BudgetBucket
      if let id = item.targetEnvelopeID { target = .envelope(id) }
      else if let id = item.targetCardID { target = .cardPayment(id) }
      else if item.sourceEnvelopeID != nil || item.sourceCardID != nil {
        target = .readyToAssign
      } else { return nil }
      let source: BudgetBucket
      if let id = item.sourceEnvelopeID { source = .envelope(id) }
      else if let id = item.sourceCardID { source = .cardPayment(id) }
      else { source = .readyToAssign }
      return AllocationLedgerItem(
        id: item.id, date: item.date, createdAt: item.createdAt,
        amountMinor: item.amountMinor, source: source, target: target
      )
    }
    var firstDates = accounts.map(\.openedAt) + allocations.map(\.date)
    var firstDescriptor = FetchDescriptor<BudgetTransaction>(sortBy: [SortDescriptor(\.date)])
    firstDescriptor.fetchLimit = 1
    if let first = try context.fetch(firstDescriptor).first { firstDates.append(first.date) }
    firstMonth = monthStart(firstDates.min() ?? Date())
  }

  private func ensureSnapshots(through requested: Date) throws {
    try prepareStaticData()
    if snapshots[requested] != nil { return }
    var month = checkpoints.keys.filter { $0 < requested }.max()
      .flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
      ?? min(firstMonth ?? requested, requested)
    while month <= requested {
      try Task.checkCancellation()
      let next = nextMonth(month)
      let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: month)
      let newlyIncludedAccount = month > (firstMonth ?? month) && accounts.contains {
        $0.openedAt >= month && $0.openedAt < next
      }
      let calculation: MonthCalculation
      if newlyIncludedAccount {
        // Transactions imported before an account's opening date become part of
        // its ledger once the account appears. Rebuild only this boundary month.
        calculation = try replayThrough(month)
      } else {
        calculation = try calculateMonth(
          month, using: accounts,
          previous: previousMonth.flatMap { checkpoints[$0] },
          previousReport: previousMonth.flatMap { balanceReports[$0] }
        )
      }
      snapshots[month] = calculation.result.snapshot
      checkpoints[month] = calculation.result.checkpoint
      balanceReports[month] = calculation.report
      month = next
    }
  }

  private func replayThrough(_ target: Date) throws -> MonthCalculation {
    let targetNext = nextMonth(target)
    let start = firstMonth ?? target
    let includedAccounts = accounts.filter { $0.openedAt < targetNext }.map { account -> AccountLedgerItem in
      var item = account
      item.openedAt = min(item.openedAt, start)
      return item
    }
    var month = start
    var previous: BudgetCalculator.Checkpoint?
    var previousReport: AccountBalanceReport?
    var latest: MonthCalculation?
    while month <= target {
      try Task.checkCancellation()
      let calculated = try calculateMonth(
        month, using: includedAccounts,
        previous: previous, previousReport: previousReport
      )
      previous = calculated.result.checkpoint
      previousReport = calculated.report
      latest = calculated
      month = nextMonth(month)
    }
    guard let latest else { throw BudgetReadError.missingSnapshot }
    return latest
  }

  private func calculateMonth(
    _ month: Date, using includedAccounts: [AccountLedgerItem],
    previous: BudgetCalculator.Checkpoint?, previousReport: AccountBalanceReport?
  ) throws -> MonthCalculation {
    let next = nextMonth(month)
    let adjustedAccounts = includedAccounts.map { account -> AccountLedgerItem in
      var adjusted = account
      if let balance = previousReport?.balances[account.id] {
        adjusted.openingBalanceMinor = balance
      }
      return adjusted
    }
    let monthTransactions = try transactions(from: month, before: next)
    let monthAllocations = allocations.filter { $0.date >= month && $0.date < next }
    let balance = report(
      before: next, inclusive: false, accounts: adjustedAccounts,
      transactions: monthTransactions, previous: previousReport,
      currencyCode: nil
    )
    let todayMonth = monthStart(Date())
    let futureAssigned = month >= todayMonth ? allocations
      .filter { $0.date >= next }
      .reduce(Int64(0)) { total, allocation in
        total + (allocation.source == .readyToAssign ? allocation.amountMinor : 0)
          - (allocation.target == .readyToAssign ? allocation.amountMinor : 0)
      } : 0
    let result = BudgetCalculator().calculateWithCheckpoint(
      month: month, accounts: includedAccounts, envelopes: envelopes,
      allocations: monthAllocations, transactions: monthTransactions,
      previous: previous, balanceReportOverride: balance,
      assignedInFutureOverride: futureAssigned
    )
    return MonthCalculation(result: result, report: balance)
  }

  private func report(
    before cutoff: Date, inclusive: Bool,
    accounts: [AccountLedgerItem], transactions: [TransactionLedgerItem],
    previous: AccountBalanceReport?, currencyCode: String?
  ) -> AccountBalanceReport {
    var result = AccountBalanceCalculator().calculate(
      before: cutoff, inclusive: inclusive,
      accounts: accounts, transactions: transactions,
      reportingCurrencyCode: currencyCode
    )
    if let previous {
      result.issues.append(contentsOf: previous.issues.filter { issue in
        switch issue {
        case .missingAccount, .overflow: true
        case .currencyMismatch, .mixedCurrencies, .positiveLiability: false
        }
      })
      if !result.issues.isEmpty { result.netWorthMinor = nil }
    }
    return result
  }

  private func transactions(from start: Date, through end: Date) throws -> [TransactionLedgerItem] {
    try fetchTransactions(start: start, end: end, inclusive: true)
  }

  private func transactions(from start: Date, before end: Date) throws -> [TransactionLedgerItem] {
    try fetchTransactions(start: start, end: end, inclusive: false)
  }

  private func fetchTransactions(start: Date, end: Date, inclusive: Bool) throws -> [TransactionLedgerItem] {
    let predicate: Predicate<BudgetTransaction>
    if inclusive {
      predicate = #Predicate { $0.date >= start && $0.date <= end }
    } else {
      predicate = #Predicate { $0.date >= start && $0.date < end }
    }
    var values: [TransactionLedgerItem] = []
    var offset = 0
    while true {
      try Task.checkCancellation()
      var descriptor = FetchDescriptor<BudgetTransaction>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt), SortDescriptor(\.id)]
      )
      descriptor.fetchLimit = 512
      descriptor.fetchOffset = offset
      let batch = try ModelContext(modelContainer).fetch(descriptor)
      values.append(contentsOf: batch.map {
        TransactionLedgerItem(
          id: $0.id, date: $0.date, createdAt: $0.createdAt,
          amountMinor: $0.amountMinor, accountID: $0.accountID,
          transferAccountID: $0.transferAccountID, envelopeID: $0.envelopeID,
          kind: $0.kind
        )
      })
      offset += batch.count
      if batch.count < 512 { break }
    }
    return values
  }

  private func monthStart(_ date: Date) -> Date {
    Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
  }

  private func nextMonth(_ date: Date) -> Date {
    Calendar.current.date(byAdding: .month, value: 1, to: date) ?? .distantFuture
  }
}

private struct MonthCalculation {
  var result: BudgetCalculator.Result
  var report: AccountBalanceReport
}

struct BudgetReadBundle: Sendable {
  var current: BudgetSnapshot
  var previous: BudgetSnapshot?
  var accountReport: AccountBalanceReport
}

private enum BudgetReadError: Error {
  case missingSnapshot
}
