import Foundation
import SwiftData

@MainActor @main
struct BankFileImportServiceChecks {
  static func main() throws {
    let container = try ModelContainer(
      for: BudgetAccount.self, BudgetTransaction.self, BudgetGroup.self,
      BudgetEnvelope.self, BudgetPayee.self, BudgetSchedule.self,
      SimpleFINImportRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let day = Calendar.current.startOfDay(for: Date())
    let account = BudgetAccount(name: "Checking", kind: .cash, currencyCode: "USD",
                                openingBalanceMinor: 20_000)
    account.openedAt = day.addingTimeInterval(-3 * 86_400)
    let group = BudgetGroup(name: "Living", sortOrder: 0)
    let food = BudgetEnvelope(groupID: group.id, name: "Food", symbol: "cart", sortOrder: 0)
    let rule = BudgetPayee(name: "Groceries", defaultEnvelopeID: food.id,
                           exactMatchText: "Groceries")
    let manual = BudgetTransaction(
      accountID: account.id, envelopeID: food.id, date: day, amountMinor: -1_000,
      payee: "Cafe", notes: "Entered by hand", kind: .expense
    )
    context.insert(account)
    context.insert(group)
    context.insert(food)
    context.insert(rule)
    context.insert(manual)
    try context.save()

    func proposal(_ id: String, _ payee: String, _ amount: Int64,
                  _ decision: BankMatchDecision) -> BankImportProposal {
      BankImportProposal(
        externalKey: "bank|\(account.id)|\(id)",
        row: BankImportRow(rowNumber: 1, date: day, amountMinor: amount,
                           payee: payee, memo: "", externalID: id),
        decision: decision
      )
    }
    let proposals = [
      proposal("match", "Cafe", -1_000, .linkManual(manual.id)),
      proposal("rule", "Groceries", -2_000, .createNew),
      BankImportProposal(
        externalKey: "bank|\(account.id)|unknown",
        row: BankImportRow(rowNumber: 3, date: day, amountMinor: -500,
                           payee: "Unrecognized Shop", memo: "Debit card purchase",
                           externalID: "unknown"),
        decision: .createNew
      ),
      proposal("income", "Paycheck", 5_000, .createNew)
    ]
    let service = BankFileImportService()
    let first = try service.save(
      proposals: proposals, account: account, existingKeys: [],
      payees: [rule], envelopes: [food], in: context
    )
    precondition(first.linked == 1 && first.created == 2
      && first.needsReview == 1 && first.skipped == 0)
    let transactions = try context.fetch(FetchDescriptor<BudgetTransaction>())
    let records = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    precondition(transactions.count == 3 && records.count == 4)
    precondition(transactions.allSatisfy { $0.kind != .expense || $0.envelopeID != nil },
                 "bank files cannot create uncategorized ledger expenses")
    precondition(manual.sourceRaw == "manualLinked" && !manual.needsApproval)
    let review = records.first { $0.payee == "Unrecognized Shop" }!
    precondition(review.status == .review && review.origin == .bankFile
      && review.transactionID == nil && review.memo == "Debit card purchase")
    let repeated = try service.save(
      proposals: proposals, account: account,
      existingKeys: Set(records.map(\.remoteKey)),
      payees: [rule], envelopes: [food], in: context
    )
    precondition(repeated.skipped == 4 && repeated.created == 0
      && repeated.needsReview == 0, "reimporting a file cannot duplicate staged rows")
    do {
      try SimpleFINSyncCoordinator.shared.resolve(review, as: .importNew, in: context)
      preconditionFailure("review must require an envelope")
    } catch BudgetCommandError.expenseNeedsEnvelope {
      // Expected.
    }
    try SimpleFINSyncCoordinator.shared.resolve(
      review, as: .importNew, envelopeID: food.id, in: context
    )
    precondition(review.status == .imported && review.transactionID != nil)
    let reviewed = try BudgetTransactionLookup.byID(review.transactionID!, in: context)!
    // Notes are only what you type; the bank's memo stays on the bank record.
    precondition(reviewed.notes.isEmpty && review.memo == "Debit card purchase")

    let legacy = BudgetTransaction(
      accountID: account.id, date: day, amountMinor: -700,
      payee: "Legacy Store", notes: "Older uncategorized entry", kind: .expense
    )
    context.insert(legacy)
    try context.save()
    let legacyProposal = proposal("legacy", "Legacy Store", -700, .linkManual(legacy.id))
    let legacySummary = try service.save(
      proposals: [legacyProposal], account: account,
      existingKeys: Set(records.map(\.remoteKey)),
      payees: [rule], envelopes: [food], in: context
    )
    precondition(legacySummary.needsReview == 1 && legacySummary.linked == 0)
    let legacyRecord = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
      .first { $0.payee == "Legacy Store" }!
    precondition(legacyRecord.transactionID == legacy.id)
    let inbox = ReviewInbox(
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()),
      records: try context.fetch(FetchDescriptor<SimpleFINImportRecord>()),
      occurrences: [], schedules: []
    )
    precondition(inbox.bankItems.count == 1,
                 "a legacy uncategorized manual entry and bank item use one review row")

    let scheduled = BudgetSchedule(
      payee: "Gym", amountMinor: 900, accountID: account.id,
      envelopeID: food.id, startDate: day, frequency: .once, notes: ""
    )
    context.insert(scheduled)
    try context.save()
    let scheduledSummary = try service.save(
      proposals: [proposal("scheduled", "Gym", -900, .createNew)],
      account: account,
      existingKeys: Set(try context.fetch(FetchDescriptor<SimpleFINImportRecord>()).map(\.remoteKey)),
      payees: [rule], envelopes: [food], in: context
    )
    precondition(scheduledSummary.created == 1 && scheduledSummary.needsReview == 0)
    let scheduledTransaction = try context.fetch(FetchDescriptor<BudgetTransaction>())
      .first { $0.payee == "Gym" }!
    precondition(scheduledTransaction.scheduleID == scheduled.id
      && scheduledTransaction.envelopeID == food.id)
    print("Bank file import checks passed")
  }
}
