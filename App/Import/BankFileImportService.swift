import Foundation
import SwiftData

struct BankFileImportSummary {
  var created: Int = 0
  var linked: Int = 0
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
    importSeparately: Set<String>,
    account: BudgetAccount,
    existingTransactions: [BudgetTransaction],
    payees: [BudgetPayee],
    envelopes: [BudgetEnvelope],
    in context: ModelContext
  ) throws -> BankFileImportSummary {
    let existingKeys = Set(existingTransactions.compactMap(\.externalKey))
    let existingByID = Dictionary(uniqueKeysWithValues: existingTransactions.map { ($0.id, $0) })
    let validEnvelopeIDs = Set(envelopes.map(\.id))
    let matcher = PayeeRuleMatcher()
    let rules = PayeeDirectory.ruleItems(payees: payees, validEnvelopeIDs: validEnvelopeIDs)
    var summary = BankFileImportSummary()
    var adjustedOpeningBalance = account.openingBalanceMinor
    for proposal in proposals {
      guard !existingKeys.contains(proposal.externalKey) else { continue }
      let willCreate: Bool
      switch proposal.decision {
      case .createNew: willCreate = true
      case .review: willCreate = importSeparately.contains(proposal.externalKey)
      case .alreadyImported, .linkManual: willCreate = false
      }
      if willCreate && proposal.row.date < account.openedAt {
        let (adjusted, overflow) = adjustedOpeningBalance.subtractingReportingOverflow(
          proposal.row.amountMinor
        )
        guard !overflow else { throw BankFileImportError.balanceOverflow }
        adjustedOpeningBalance = adjusted
      }
      guard case .linkManual(let id) = proposal.decision,
            !existingKeys.contains(proposal.externalKey) else { continue }
      guard let transaction = existingByID[id],
            transaction.externalKey == nil,
            transaction.sourceRaw == "manual" else {
        throw BankFileImportError.previewChanged
      }
    }
    for proposal in proposals {
      if existingKeys.contains(proposal.externalKey) {
        summary.skipped += 1
        continue
      }
      switch proposal.decision {
      case .alreadyImported:
        summary.skipped += 1
      case .linkManual(let id):
        guard let transaction = existingByID[id] else { continue }
        transaction.externalKey = proposal.externalKey
        transaction.sourceRaw = "manualLinked"
        transaction.isCleared = true
        summary.linked += 1
      case .review:
        if importSeparately.contains(proposal.externalKey) {
          insert(proposal, account: account, rules: rules, matcher: matcher, in: context)
          summary.created += 1
        } else {
          summary.skipped += 1
        }
      case .createNew:
        insert(proposal, account: account, rules: rules, matcher: matcher, in: context)
        summary.created += 1
      }
    }
    let openingChanged = adjustedOpeningBalance != account.openingBalanceMinor
    account.openingBalanceMinor = adjustedOpeningBalance
    if openingChanged || proposals.contains(where: {
      if let reconciled = account.lastReconciledAt {
        return $0.row.date <= reconciled && !existingKeys.contains($0.externalKey)
      }
      return false
    }) {
      account.lastReconciledAt = nil
      account.lastReconciledBalanceMinor = nil
    }
    try context.save()
    return summary
  }

  private func insert(
    _ proposal: BankImportProposal,
    account: BudgetAccount,
    rules: [PayeeRuleItem],
    matcher: PayeeRuleMatcher,
    in context: ModelContext
  ) {
    let row = proposal.row
    let kind: BudgetTransactionKind = row.amountMinor < 0 ? .expense : .inflow
    let transaction = BudgetTransaction(
      accountID: account.id,
      envelopeID: kind == .expense
        ? matcher.envelopeID(for: row.payee, rules: rules) : nil,
      date: row.date,
      amountMinor: row.amountMinor,
      payee: row.payee,
      notes: row.memo,
      kind: kind
    )
    transaction.externalKey = proposal.externalKey
    transaction.sourceRaw = "bankFile"
    transaction.isCleared = true
    transaction.needsApproval = true
    context.insert(transaction)
  }
}
