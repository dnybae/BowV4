import Foundation
import SwiftData

/// Saves the selected transaction and its future plan together, without historical backfilling.
struct TransactionScheduling {
  @discardableResult
  static func save(
    transaction: BudgetTransaction? = nil,
    kind: BudgetTransactionKind, account: BudgetAccount, destination: BudgetAccount?,
    envelopeID: UUID?, amountMinor: Int64, payee: String, merchantDomain: String? = nil,
    notes: String, timing: TransactionTiming, in context: ModelContext
  ) throws -> BudgetSchedule? {
    do {
      if timing.isFuture, let transaction {
        let id: UUID? = transaction.id
        let bankRecords = try context.fetchCount(FetchDescriptor<SimpleFINImportRecord>(
          predicate: #Predicate { $0.transactionID == id }
        ))
        guard transaction.sourceRaw == "manual", !transaction.isCleared,
              !transaction.destinationIsCleared, transaction.scheduleID == nil, bankRecords == 0 else {
          throw SchedulingError.confirmedTransaction
        }
      }
      var schedule: BudgetSchedule?
      if let frequency = timing.scheduleFrequency {
        schedule = try BudgetCommands.addSchedule(
          kind: kind, account: account, destination: destination, envelopeID: envelopeID,
          amountMinor: amountMinor, startDate: timing.date, frequency: frequency,
          payee: payee, notes: notes, in: context, saving: false
        )
        // The selected past/today transaction is recorded explicitly below. All intervening
        // dates, including today when the anchor is older, are already reviewed.
        schedule?.reviewedThrough = timing.calendar.startOfDay(for: timing.now)
      }
      if timing.isFuture {
        if let transaction {
          // Invalidate its old effect and reconciliation before converting it to a future plan.
          try BudgetCommands.deleteTransaction(transaction, in: context, saving: false)
        }
      } else if let transaction {
        try BudgetCommands.updateTransaction(
          transaction, kind: kind, account: account, destination: destination,
          envelopeID: envelopeID, amountMinor: amountMinor, date: timing.date,
          payee: payee, merchantDomain: merchantDomain, notes: notes,
          scheduleID: schedule?.id, scheduledFor: schedule == nil ? nil : timing.date,
          in: context, saving: false
        )
      } else {
        try BudgetCommands.addTransaction(
          kind: kind, account: account, destination: destination, envelopeID: envelopeID,
          amountMinor: amountMinor, date: timing.date, payee: payee,
          merchantDomain: merchantDomain, notes: notes,
          scheduleID: schedule?.id, scheduledFor: schedule == nil ? nil : timing.date,
          in: context, saving: false
        )
      }
      try context.save()
      if schedule != nil { try? ScheduleTargetSynchronizer().refresh(in: context, today: timing.now) }
      return schedule
    } catch {
      context.rollback()
      throw error
    }
  }
}

private enum SchedulingError: LocalizedError {
  case confirmedTransaction

  var errorDescription: String? {
    "A transaction confirmed by the bank or entered from a schedule can’t be moved into the future. Add a new scheduled transaction instead."
  }
}
