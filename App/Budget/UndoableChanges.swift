import Foundation
import SwiftData

/// Changes that can be taken back from their toast's Undo button.
@MainActor
enum UndoableChanges {
  typealias Action = @MainActor () throws -> Void

  /// Restore the transaction and the bank/schedule references changed by deletion together.
  /// Reconciliation remains invalidated so a later reconciliation is never overwritten.
  static func delete(_ transaction: BudgetTransaction, in context: ModelContext) throws -> Action {
    let copy = BowBackup.Transaction(transaction)
    let id = transaction.id
    let records = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate { $0.transactionID == id }))
    let recordCopies = records.map(BowBackup.BankRecord.init)
    let scheduleID = transaction.scheduleID
    let scheduledFor = transaction.scheduledFor
    let priorOccurrence = try occurrence(scheduleID: scheduleID, date: scheduledFor, in: context).map(BowBackup.Occurrence.init)
    do { try BudgetCommands.deleteTransaction(transaction, in: context) }
    catch { context.rollback(); throw error }
    let changedOccurrenceID = try occurrence(scheduleID: scheduleID, date: scheduledFor, in: context)?.id
    let afterRecords = records.map { ($0.id, $0.statusRaw, $0.transactionID) }
    return {
      do {
        guard try BudgetTransactionLookup.byID(id, in: context) == nil else { throw UndoError.changed }
        try validateAccount(copy.accountID, in: context)
        if let destination = copy.transferAccountID { try validateAccount(destination, in: context) }
        let currentRecords = try afterRecords.map { expected -> SimpleFINImportRecord in
          let recordID = expected.0
          guard let record = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate { $0.id == recordID })).first,
                record.statusRaw == expected.1, record.transactionID == expected.2 else { throw UndoError.changed }
          return record
        }
        context.insert(copy.model)
        for (record, before) in zip(currentRecords, recordCopies) {
          record.transactionID = before.transactionID
          record.statusRaw = before.statusRaw
          record.originalManualSnapshot = before.originalManualSnapshot
          record.matchedAutomatically = before.matchedAutomatically
        }
        try restoreOccurrence(changedID: changedOccurrenceID, before: priorOccurrence, in: context)
        try context.save()
      } catch { context.rollback(); throw error }
    }
  }

  static func ignore(_ record: SimpleFINImportRecord, in context: ModelContext) throws -> Action {
    let id = record.id
    let before = BowBackup.BankRecord(record)
    let transaction = try record.transactionID.flatMap { try BudgetTransactionLookup.byID($0, in: context) }
    let removed = record.status == .imported ? transaction.map(BowBackup.Transaction.init) : nil
    do { try SimpleFINSyncCoordinator.shared.resolve(record, as: .ignore, in: context) }
    catch { context.rollback(); throw error }
    return {
      do {
        guard let current = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate { $0.id == id })).first,
              current.status == .ignored, current.transactionID == nil else { throw UndoError.changed }
        if let removed {
          try validateAccount(removed.accountID, in: context)
          guard try BudgetTransactionLookup.byID(removed.id, in: context) == nil else { throw UndoError.changed }
          context.insert(removed.model)
        }
        current.statusRaw = before.statusRaw
        current.transactionID = before.transactionID
        try context.save()
      } catch { context.rollback(); throw error }
    }
  }

  static func skip(scheduleID: UUID, date: Date, in context: ModelContext) throws -> Action {
    let before = try occurrence(scheduleID: scheduleID, date: date, in: context).map(BowBackup.Occurrence.init)
    do {
      try BudgetCommands.skipScheduledDate(scheduleID: scheduleID, on: date, in: context)
      try context.save()
    } catch { context.rollback(); throw error }
    let changedID = try occurrence(scheduleID: scheduleID, date: date, in: context)?.id
    return {
      do {
        guard try BudgetTransactionLookup.scheduled(scheduleID: scheduleID, on: date, in: context) == nil else { throw UndoError.changed }
        try restoreOccurrence(changedID: changedID, before: before, in: context)
        try context.save()
      } catch { context.rollback(); throw error }
    }
  }

  static func setHidden(_ envelope: BudgetEnvelope, hidden: Bool, availableMinor: Int64, in context: ModelContext) throws -> Action? {
    let id = envelope.id
    let before = envelope.isHidden
    do { try BudgetCommands.setEnvelopeHidden(envelope, hidden: hidden, availableMinor: availableMinor, in: context) }
    catch { context.rollback(); throw error }
    // Hiding can always be undone by revealing the envelope. Re-hiding after Unhide
    // needs a fresh ledger check, so Unhide only confirms the action.
    guard !before && hidden else { return nil }
    return {
      do {
        guard let current = try context.fetch(FetchDescriptor<BudgetEnvelope>(predicate: #Predicate { $0.id == id })).first,
              current.isHidden == hidden else { throw UndoError.changed }
        try BudgetCommands.setEnvelopeHidden(current, hidden: false, availableMinor: 0, in: context)
      } catch { context.rollback(); throw error }
    }
  }

  static func undoMove(_ allocation: BudgetAllocation, in context: ModelContext) -> Action {
    let id = allocation.id
    return {
      do {
        guard let item = try context.fetch(FetchDescriptor<BudgetAllocation>(predicate: #Predicate { $0.id == id })).first else { throw UndoError.changed }
        context.delete(item)
        try context.save()
      } catch { context.rollback(); throw error }
    }
  }

  private static func validateAccount(_ id: UUID, in context: ModelContext) throws {
    guard let account = try context.fetch(FetchDescriptor<BudgetAccount>(predicate: #Predicate { $0.id == id })).first,
          account.closedAt == nil else { throw UndoError.changed }
  }

  private static func occurrence(scheduleID: UUID?, date: Date?, in context: ModelContext) throws -> BudgetScheduleOccurrence? {
    guard let scheduleID, let date else { return nil }
    return try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>(predicate: #Predicate { $0.scheduleID == scheduleID }))
      .first { Calendar.current.isDate($0.scheduledFor, inSameDayAs: date) }
  }

  private static func restoreOccurrence(changedID: UUID?, before: BowBackup.Occurrence?, in context: ModelContext) throws {
    guard let changedID else { return }
    guard let current = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>(predicate: #Predicate { $0.id == changedID })).first,
          current.isSkipped else { throw UndoError.changed }
    if let before { current.isSkipped = before.isSkipped }
    else { context.delete(current) }
  }

  enum UndoError: LocalizedError {
    case changed
    var errorDescription: String? { "This item changed since the action. Open it again to review its current state." }
  }
}
