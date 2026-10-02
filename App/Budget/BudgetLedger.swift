import Foundation

struct BudgetLedger {
  static func snapshot(
    month: Date,
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    allocations: [BudgetAllocation],
    transactions: [BudgetTransaction]
  ) -> BudgetSnapshot {
    BudgetCalculator().calculate(
      month: month,
      accounts: accountItems(accounts),
      envelopes: envelopes.map { EnvelopeLedgerItem(id: $0.id, paymentAccountID: $0.paymentAccountID) },
      allocations: allocations.compactMap { allocation in
        let target: BudgetBucket
        if let envelopeID = allocation.targetEnvelopeID {
          target = .envelope(envelopeID)
        } else if let cardID = allocation.targetCardID {
          target = .cardPayment(cardID)
        } else if allocation.sourceEnvelopeID != nil || allocation.sourceCardID != nil {
          target = .readyToAssign
        } else {
          return nil
        }
        let source: BudgetBucket
        if let envelopeID = allocation.sourceEnvelopeID {
          source = .envelope(envelopeID)
        } else if let cardID = allocation.sourceCardID {
          source = .cardPayment(cardID)
        } else {
          source = .readyToAssign
        }
        return AllocationLedgerItem(
          id: allocation.id,
          date: allocation.date,
          createdAt: allocation.createdAt,
          amountMinor: allocation.amountMinor,
          source: source,
          target: target
        )
      },
      transactions: transactionItems(transactions)
    )
  }

  static func accountBalanceReport(
    before cutoff: Date,
    inclusive: Bool = false,
    accounts: [BudgetAccount],
    transactions: [BudgetTransaction],
    currencyCode: String? = nil
  ) -> AccountBalanceReport {
    AccountBalanceCalculator().calculate(
      before: cutoff,
      inclusive: inclusive,
      accounts: accountItems(accounts),
      transactions: transactionItems(transactions),
      reportingCurrencyCode: currencyCode
    )
  }

  private static func accountItems(_ accounts: [BudgetAccount]) -> [AccountLedgerItem] {
    accounts.map {
      AccountLedgerItem(
        id: $0.id,
        kind: $0.kind,
        openingBalanceMinor: $0.openingBalanceMinor,
        openedAt: $0.openedAt,
        currencyCode: $0.currencyCode
      )
    }
  }

  private static func transactionItems(_ transactions: [BudgetTransaction]) -> [TransactionLedgerItem] {
    transactions.map {
      TransactionLedgerItem(
        id: $0.id,
        date: $0.date,
        createdAt: $0.createdAt,
        amountMinor: $0.amountMinor,
        accountID: $0.accountID,
        transferAccountID: $0.transferAccountID,
        envelopeID: $0.envelopeID,
        kind: $0.kind,
        isBeforeStart: $0.isBeforeStart
      )
    }
  }
}
