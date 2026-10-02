import Foundation
import SwiftData

/// Brings a budget saved by an earlier build into the current shape, one numbered step at a time.
/// The step reached is stored in the budget itself, so the demo budget can never mark the real
/// one as done. Every step keeps each account's current balance exactly where it was.
struct BowDataUpgrade {
  static let currentVersion = 2
  var calendar: Calendar = .current

  func run(in context: ModelContext) throws {
    guard let profile = try context.fetch(FetchDescriptor<BudgetProfile>()).first,
          profile.dataVersion < Self.currentVersion else { return }
    if profile.dataVersion < 1 {
      try BankMemoNotesCleanup().clear(in: context)
    }
    if profile.dataVersion < 2 {
      try normalizeDays(in: context)
      try moveHistoryIntoStartingBalances(in: context)
    }
    profile.dataVersion = Self.currentVersion
    try context.save()
  }

  /// Version 2: transactions are calendar days. Bank items are re-read the way imports now read
  /// them, so a midnight-UTC posting lands on the bank's own date.
  private func normalizeDays(in context: ModelContext) throws {
    for transaction in try context.fetch(FetchDescriptor<BudgetTransaction>()) {
      let day = transaction.sourceRaw == BankImportOrigin.simplefin.rawValue
        ? BowDay.fromBankTimestamp(transaction.date.timeIntervalSince1970, calendar: calendar)
        : BowDay.normalized(transaction.date, calendar: calendar)
      if transaction.date != day { transaction.date = day }
    }
    for record in try context.fetch(FetchDescriptor<SimpleFINImportRecord>()) {
      let day = record.remoteKey.hasPrefix("simplefin|")
        ? BowDay.fromBankTimestamp(record.date.timeIntervalSince1970, calendar: calendar)
        : BowDay.normalized(record.date, calendar: calendar)
      if record.date != day { record.date = day }
    }
  }

  /// Version 2: an account's starting balance is as of the start of a day, and anything dated
  /// earlier is history the starting balance already includes. Earlier builds counted that
  /// history in the balance instead, so its total moves into the starting balance.
  private func moveHistoryIntoStartingBalances(in context: ModelContext) throws {
    let accounts = try context.fetch(FetchDescriptor<BudgetAccount>())
    var byID: [UUID: BudgetAccount] = [:]
    for account in accounts {
      account.openedAt = BowDay.start(of: account.openedAt, calendar: calendar)
      byID[account.id] = account
    }
    for transaction in try context.fetch(FetchDescriptor<BudgetTransaction>()) {
      guard let source = byID[transaction.accountID] else { continue }
      let destination = transaction.kind == .transfer ? transaction.transferAccountID.flatMap { byID[$0] } : nil
      let beforeStart = BudgetCommands.isBeforeStart(date: transaction.date, account: source, destination: destination)
      guard beforeStart, !transaction.isBeforeStart else { continue }
      transaction.isBeforeStart = true
      source.openingBalanceMinor += transaction.amountMinor
      destination?.openingBalanceMinor -= transaction.amountMinor
    }
  }
}
