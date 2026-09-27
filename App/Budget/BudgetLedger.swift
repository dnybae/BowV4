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
      accounts: accounts.map {
        AccountLedgerItem(
          id: $0.id,
          kind: $0.kind,
          openingBalanceMinor: $0.openingBalanceMinor,
          openedAt: $0.openedAt
        )
      },
      envelopes: envelopes.map { EnvelopeLedgerItem(id: $0.id) },
      allocations: allocations.compactMap { allocation in
        let target: BudgetBucket
        if let envelopeID = allocation.targetEnvelopeID {
          target = .envelope(envelopeID)
        } else if let cardID = allocation.targetCardID {
          target = .cardPayment(cardID)
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
      transactions: transactions.map {
        TransactionLedgerItem(
          id: $0.id,
          date: $0.date,
          createdAt: $0.createdAt,
          amountMinor: $0.amountMinor,
          accountID: $0.accountID,
          transferAccountID: $0.transferAccountID,
          envelopeID: $0.envelopeID,
          kind: $0.kind
        )
      }
    )
  }
}
