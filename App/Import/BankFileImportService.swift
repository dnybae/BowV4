import Foundation
import SwiftData

struct BankFileImportSummary {
  var created: Int = 0
  var linked: Int = 0
  var needsReview: Int = 0
  var skipped: Int = 0
}

enum BankFileImportError: LocalizedError {
  case previewChanged
  case balanceOverflow

  var errorDescription: String? {
    switch self {
    case .previewChanged: "Transactions changed since the preview. Preview the file again before importing."
    case .balanceOverflow: "The historical balance adjustment is too large to import safely."
    }
  }
}

struct BankFileImportService {
  func save(
    proposals: [BankImportProposal],
    account: BudgetAccount,
    existingKeys: Set<String>,
    payees: [BudgetPayee],
    envelopes: [BudgetEnvelope],
    in context: ModelContext
  ) throws -> BankFileImportSummary {
    let linkedIDs = Set(proposals.compactMap { proposal -> UUID? in
      if case .linkManual(let id) = proposal.decision { return id }
      return nil
    })
    var existingByID: [UUID: BudgetTransaction] = [:]
    for id in linkedIDs {
      existingByID[id] = try BudgetTransactionLookup.byID(id, in: context)
    }
    let validEnvelopeIDs = Set(envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil
    }.map(\.id))
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let rules = PayeeDirectory.ruleItems(payees: payees, validEnvelopeIDs: validEnvelopeIDs)
    let matcher = PayeeRuleMatcher()
    var summary = BankFileImportSummary()

    for proposal in proposals where !existingKeys.contains(proposal.externalKey) {
      guard case .linkManual(let id) = proposal.decision else { continue }
      guard let transaction = existingByID[id], transaction.externalKey == nil,
            transaction.sourceRaw == "manual", transaction.accountID == account.id else {
        throw BankFileImportError.previewChanged
      }
    }

    for proposal in proposals {
      if existingKeys.contains(proposal.externalKey) {
        summary.skipped += 1
        continue
      }
      let row = proposal.row
      let scheduledTransfer = schedules.contains { schedule in
        guard schedule.isActive && schedule.kind == .transfer,
              ScheduleRecurrence().occurs(
                starting: schedule.startDate, frequency: schedule.frequency, on: row.date
              ) else { return false }
        return (schedule.accountID == account.id && row.amountMinor == -schedule.amountMinor)
          || (schedule.transferAccountID == account.id && row.amountMinor == schedule.amountMinor)
      }
      let envelopeID = row.amountMinor < 0
        ? matcher.envelopeID(for: row.payee, rules: rules) : nil
      let scheduledExpense = schedules.filter { schedule in
        schedule.isActive && schedule.kind == .expense
          && schedule.accountID == account.id
          && row.amountMinor == -schedule.amountMinor
          && PayeeDirectory.isSamePayee(schedule.payee, row.payee, payees: payees)
          && ScheduleRecurrence().occurs(
            starting: schedule.startDate, frequency: schedule.frequency, on: row.date
          )
      }
      let matchedSchedule = scheduledExpense.count == 1 ? scheduledExpense.first : nil
      let scheduleAlreadyRecorded = try matchedSchedule.map { schedule in
        try BudgetTransactionLookup.scheduled(
          scheduleID: schedule.id, on: row.date, in: context
        ) != nil
      } ?? false
      let scheduleNeedsReview = scheduledExpense.count > 1 || scheduleAlreadyRecorded
      let selectedEnvelopeID = matchedSchedule?.envelopeID ?? envelopeID
      // Rows from before the account's starting balance come in as history: the starting
      // balance already includes them, so they need no envelope and change no balance.
      let beforeStart = BowDay.normalized(row.date) < BowDay.start(of: account.openedAt)
      switch proposal.decision {
      case .alreadyImported:
        summary.skipped += 1
      case .linkManual(let id) where !scheduledTransfer && scheduledExpense.count <= 1
        && (row.amountMinor >= 0 || existingByID[id]?.envelopeID != nil)
        && scheduleCompatible(existingByID[id], with: matchedSchedule):
        guard let transaction = existingByID[id] else { throw BankFileImportError.previewChanged }
        let record = record(for: proposal, account: account, in: context)
        record.originalManualSnapshot = try JSONEncoder().encode(ManualTransactionSnapshot(transaction))
        transaction.externalKey = proposal.externalKey
        transaction.sourceRaw = "manualLinked"
        transaction.isCleared = true
        transaction.needsApproval = false
        if let matchedSchedule, transaction.scheduleID == nil {
          transaction.scheduleID = matchedSchedule.id
          transaction.scheduledFor = row.date
        }
        record.transactionID = transaction.id
        record.status = .linked
        record.matchedAutomatically = true
        summary.linked += 1
        if let reconciled = account.lastReconciledAt, row.date <= reconciled {
          account.lastReconciledAt = nil
          account.lastReconciledBalanceMinor = nil
        }
      case .createNew where !scheduledTransfer && !scheduleNeedsReview
        && (row.amountMinor >= 0 || selectedEnvelopeID != nil || beforeStart):
        let transaction = BudgetTransaction(
          accountID: account.id, envelopeID: selectedEnvelopeID, date: row.date,
          amountMinor: row.amountMinor, payee: row.payee, notes: "",
          kind: row.amountMinor < 0 ? .expense : .inflow
        )
        transaction.externalKey = proposal.externalKey
        transaction.sourceRaw = BankImportOrigin.bankFile.rawValue
        transaction.isCleared = true
        if let matchedSchedule {
          transaction.scheduleID = matchedSchedule.id
          transaction.scheduledFor = row.date
        }
        transaction.isBeforeStart = beforeStart
        context.insert(transaction)
        let record = record(for: proposal, account: account, in: context)
        record.transactionID = transaction.id
        record.status = .imported
        summary.created += 1
      case .linkManual(let id):
        let record = record(for: proposal, account: account, in: context)
        record.transactionID = id
        summary.needsReview += 1
      case .createNew, .review:
        _ = record(for: proposal, account: account, in: context)
        summary.needsReview += 1
      }
      if let reconciled = account.lastReconciledAt, row.date <= reconciled,
         case .createNew = proposal.decision, selectedEnvelopeID != nil || row.amountMinor >= 0 || beforeStart {
        account.lastReconciledAt = nil
        account.lastReconciledBalanceMinor = nil
      }
    }
    try context.save()
    return summary
  }

  private func record(
    for proposal: BankImportProposal, account: BudgetAccount, in context: ModelContext
  ) -> SimpleFINImportRecord {
    let row = proposal.row
    let record = SimpleFINImportRecord(
      remoteKey: proposal.externalKey, localAccountID: account.id,
      date: row.date, amountMinor: row.amountMinor, payee: row.payee
    )
    record.origin = .bankFile
    record.bankState = .posted
    record.memo = row.memo
    context.insert(record)
    return record
  }

  private func scheduleCompatible(
    _ transaction: BudgetTransaction?, with schedule: BudgetSchedule?
  ) -> Bool {
    guard let schedule else { return true }
    guard let transaction else { return false }
    return (transaction.scheduleID == nil || transaction.scheduleID == schedule.id)
      && (schedule.envelopeID == nil || transaction.envelopeID == schedule.envelopeID)
  }
}
