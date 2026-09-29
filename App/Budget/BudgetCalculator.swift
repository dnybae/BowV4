import Foundation

struct BudgetCalculator {
  var calendar: Calendar = .current

  func calculate(
    month: Date,
    accounts: [AccountLedgerItem],
    envelopes: [EnvelopeLedgerItem],
    allocations: [AllocationLedgerItem],
    transactions: [TransactionLedgerItem]
  ) -> BudgetSnapshot {
    let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? month
    let includedAccounts = accounts.filter { $0.openedAt < nextMonth }
    let accountKinds = Dictionary(uniqueKeysWithValues: includedAccounts.map { ($0.id, $0.kind) })
    let balanceReport = AccountBalanceCalculator().calculate(
      before: nextMonth, accounts: accounts, transactions: transactions
    )
    let accountBalances = balanceReport.balances
    var cashAvailable = Dictionary(uniqueKeysWithValues: envelopes
      .filter { $0.paymentAccountID == nil }.map { ($0.id, Int64(0)) })
    var cashShortfall: [UUID: Int64] = [:]
    var paymentAvailable = Dictionary(uniqueKeysWithValues: includedAccounts
      .filter { $0.kind == .credit }
      .map { ($0.id, Int64(0)) })
    var creditShortfall: [CardEnvelopeKey: Int64] = [:]
    var categoryCardReserve: [CardEnvelopeKey: Int64] = [:]
    var assigned: [UUID: Int64] = [:]
    var activity: [UUID: Int64] = [:]

    let events: [LedgerEvent] =
      allocations.filter { $0.date < nextMonth }.map { .allocation($0) }
      + transactions.filter { $0.date < nextMonth }.map { .transaction($0) }
    let orderedEvents = events.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    var activeMonth = calendar.dateInterval(
      of: .month,
      for: orderedEvents.first?.date ?? monthStart
    )?.start ?? monthStart

    for event in orderedEvents {
      let eventMonth = calendar.dateInterval(of: .month, for: event.date)?.start ?? event.date
      if eventMonth > activeMonth {
        rollForward(
          cashAvailable: &cashAvailable,
          cashShortfall: &cashShortfall,
          paymentAvailable: &paymentAvailable,
          creditShortfall: &creditShortfall
        )
        activeMonth = eventMonth
      }

      switch event {
      case .allocation(let allocation):
        guard allocation.amountMinor > 0 else { continue }
        switch allocation.source {
        case .readyToAssign:
          break
        case .envelope(let id):
          cashAvailable[id, default: 0] -= allocation.amountMinor
        case .cardPayment(let id):
          paymentAvailable[id, default: 0] -= allocation.amountMinor
          consumeCardReserves(
            cardID: id,
            amount: allocation.amountMinor,
            categoryCardReserve: &categoryCardReserve
          )
        }

        switch allocation.target {
        case .readyToAssign:
          break
        case .cardPayment(let id):
          paymentAvailable[id, default: 0] += allocation.amountMinor
        case .envelope(let id):
          var remaining = allocation.amountMinor
          let cashCovered = min(remaining, cashShortfall[id, default: 0])
          cashShortfall[id, default: 0] -= cashCovered
          remaining -= cashCovered
          let keys = creditShortfall.keys
            .filter { $0.envelopeID == id }
            .sorted { $0.cardID.uuidString < $1.cardID.uuidString }
          for key in keys {
            let covered = min(remaining, creditShortfall[key, default: 0])
            guard covered > 0 else { continue }
            creditShortfall[key, default: 0] -= covered
            paymentAvailable[key.cardID, default: 0] += covered
            categoryCardReserve[key, default: 0] += covered
            remaining -= covered
          }
          cashAvailable[id, default: 0] += remaining
        }

        if eventMonth == monthStart {
          if case .envelope(let id) = allocation.source {
            assigned[id, default: 0] -= allocation.amountMinor
          }
          if case .envelope(let id) = allocation.target {
            assigned[id, default: 0] += allocation.amountMinor
          }
        }

      case .transaction(let transaction):
        guard let kind = accountKinds[transaction.accountID] else { continue }
        if transaction.kind == .transfer {
          guard let destinationID = transaction.transferAccountID,
                accountKinds[destinationID] != nil else { continue }
        }
        if transaction.kind == .transfer {
          let destinationID = transaction.transferAccountID!
          let destinationKind = accountKinds[destinationID]!
          if kind == .cash && destinationKind == .credit {
            let fundedPayment = min(
              -transaction.amountMinor,
              max(0, paymentAvailable[destinationID, default: 0])
            )
            paymentAvailable[destinationID, default: 0] -= fundedPayment
            consumeCardReserves(
              cardID: destinationID,
              amount: fundedPayment,
              categoryCardReserve: &categoryCardReserve
            )
          }
          if kind == .cash && destinationKind.isTracking,
             let envelopeID = transaction.envelopeID {
            spendCash(
              -transaction.amountMinor,
              from: envelopeID,
              cashAvailable: &cashAvailable,
              cashShortfall: &cashShortfall
            )
            if eventMonth == monthStart {
              activity[envelopeID, default: 0] += transaction.amountMinor
            }
          }
          continue
        }

        guard let envelopeID = transaction.envelopeID else { continue }
        if kind == .cash {
          if transaction.amountMinor < 0 {
            spendCash(
              -transaction.amountMinor,
              from: envelopeID,
              cashAvailable: &cashAvailable,
              cashShortfall: &cashShortfall
            )
          } else {
            let recovered = min(transaction.amountMinor, cashShortfall[envelopeID, default: 0])
            cashShortfall[envelopeID, default: 0] -= recovered
            cashAvailable[envelopeID, default: 0] += transaction.amountMinor - recovered
          }
          if eventMonth == monthStart {
            activity[envelopeID, default: 0] += transaction.amountMinor
          }
        } else if kind == .credit {
          let key = CardEnvelopeKey(cardID: transaction.accountID, envelopeID: envelopeID)
          if transaction.amountMinor < 0 {
            let spent = -transaction.amountMinor
            let funded = min(spent, max(0, cashAvailable[envelopeID, default: 0]))
            cashAvailable[envelopeID, default: 0] -= funded
            creditShortfall[key, default: 0] += spent - funded
            paymentAvailable[transaction.accountID, default: 0] += funded
            categoryCardReserve[key, default: 0] += funded
            if eventMonth == monthStart {
              activity[envelopeID, default: 0] -= spent
            }
          } else if transaction.amountMinor > 0 {
            var remaining = transaction.amountMinor
            let debtReversed = min(remaining, creditShortfall[key, default: 0])
            creditShortfall[key, default: 0] -= debtReversed
            remaining -= debtReversed
            let reserveReleased = min(
              remaining,
              categoryCardReserve[key, default: 0],
              max(0, paymentAvailable[transaction.accountID, default: 0])
            )
            categoryCardReserve[key, default: 0] -= reserveReleased
            paymentAvailable[transaction.accountID, default: 0] -= reserveReleased
            cashAvailable[envelopeID, default: 0] += reserveReleased
            if eventMonth == monthStart {
              activity[envelopeID, default: 0] += debtReversed + reserveReleased
            }
          }
        }
      }
    }

    if monthStart > activeMonth {
      rollForward(
        cashAvailable: &cashAvailable,
        cashShortfall: &cashShortfall,
        paymentAvailable: &paymentAvailable,
        creditShortfall: &creditShortfall
      )
    }

    let cashTotal = includedAccounts
      .filter { $0.kind == .cash }
      .reduce(Int64(0)) { $0 + accountBalances[$1.id, default: 0] }
    let envelopeFunds = cashAvailable.values.reduce(Int64(0), +)
    let cardPaymentFunds = paymentAvailable.values.reduce(Int64(0), +)
    let todayMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    let assignedInFuture = allocations.filter { monthStart >= todayMonth && $0.date >= nextMonth }.reduce(Int64(0)) { total, allocation in
      let fromReady = allocation.source == .readyToAssign
      let toReady = allocation.target == .readyToAssign
      return total + (fromReady ? allocation.amountMinor : 0) - (toReady ? allocation.amountMinor : 0)
    }
    let creditShortfallByEnvelope = Dictionary(
      creditShortfall.map { ($0.key.envelopeID, $0.value) },
      uniquingKeysWith: +
    )
    return BudgetSnapshot(
      month: monthStart,
      accountBalances: accountBalances,
      cashAvailable: cashAvailable,
      cashShortfall: cashShortfall,
      creditShortfall: creditShortfallByEnvelope,
      paymentAvailable: paymentAvailable,
      assigned: assigned,
      activity: activity,
      readyToAssignMinor: cashTotal - envelopeFunds - cardPaymentFunds - assignedInFuture,
      assignedInFutureMinor: assignedInFuture,
      cashTotalMinor: cashTotal,
      netWorthMinor: balanceReport.netWorthMinor
    )
  }

  private func rollForward(
    cashAvailable: inout [UUID: Int64],
    cashShortfall: inout [UUID: Int64],
    paymentAvailable: inout [UUID: Int64],
    creditShortfall: inout [CardEnvelopeKey: Int64]
  ) {
    for id in cashAvailable.keys where cashAvailable[id, default: 0] < 0 {
      cashAvailable[id] = 0
    }
    for id in paymentAvailable.keys where paymentAvailable[id, default: 0] < 0 {
      paymentAvailable[id] = 0
    }
    cashShortfall.removeAll()
    creditShortfall.removeAll()
  }

  private func spendCash(
    _ amount: Int64,
    from envelopeID: UUID,
    cashAvailable: inout [UUID: Int64],
    cashShortfall: inout [UUID: Int64]
  ) {
    let funded = min(amount, max(0, cashAvailable[envelopeID, default: 0]))
    cashAvailable[envelopeID, default: 0] -= funded
    cashShortfall[envelopeID, default: 0] += amount - funded
  }

  private func consumeCardReserves(
    cardID: UUID,
    amount: Int64,
    categoryCardReserve: inout [CardEnvelopeKey: Int64]
  ) {
    var remaining = amount
    let keys = categoryCardReserve.keys
      .filter { $0.cardID == cardID }
      .sorted { $0.envelopeID.uuidString < $1.envelopeID.uuidString }
    for key in keys {
      let used = min(remaining, categoryCardReserve[key, default: 0])
      categoryCardReserve[key, default: 0] -= used
      remaining -= used
      if remaining == 0 { break }
    }
  }
}

struct AccountLedgerItem {
  var id: UUID
  var kind: BudgetAccountKind
  var openingBalanceMinor: Int64
  var openedAt: Date
  var currencyCode: String = "USD"
}

struct EnvelopeLedgerItem {
  var id: UUID
  var paymentAccountID: UUID? = nil
}

enum BudgetBucket: Hashable {
  case readyToAssign
  case envelope(UUID)
  case cardPayment(UUID)
}

struct AllocationLedgerItem {
  var id: UUID
  var date: Date
  var createdAt: Date
  var amountMinor: Int64
  var source: BudgetBucket
  var target: BudgetBucket
}

struct TransactionLedgerItem {
  var id: UUID
  var date: Date
  var createdAt: Date
  var amountMinor: Int64
  var accountID: UUID
  var transferAccountID: UUID?
  var envelopeID: UUID?
  var kind: BudgetTransactionKind
}

struct BudgetSnapshot {
  var month: Date
  var accountBalances: [UUID: Int64]
  var cashAvailable: [UUID: Int64]
  var cashShortfall: [UUID: Int64]
  var creditShortfall: [UUID: Int64]
  var paymentAvailable: [UUID: Int64]
  var assigned: [UUID: Int64]
  var activity: [UUID: Int64]
  var readyToAssignMinor: Int64
  var assignedInFutureMinor: Int64 = 0
  var cashTotalMinor: Int64
  var netWorthMinor: Int64?

  func available(for envelopeID: UUID) -> Int64 {
    cashAvailable[envelopeID, default: 0]
      - cashShortfall[envelopeID, default: 0]
      - creditShortfall[envelopeID, default: 0]
  }
}

private struct CardEnvelopeKey: Hashable {
  var cardID: UUID
  var envelopeID: UUID
}

private enum LedgerEvent {
  case allocation(AllocationLedgerItem)
  case transaction(TransactionLedgerItem)

  var id: UUID {
    switch self {
    case .allocation(let value): value.id
    case .transaction(let value): value.id
    }
  }

  var date: Date {
    switch self {
    case .allocation(let value): value.date
    case .transaction(let value): value.date
    }
  }

  var createdAt: Date {
    switch self {
    case .allocation(let value): value.createdAt
    case .transaction(let value): value.createdAt
    }
  }
}

private extension BudgetAccountKind {
  var isTracking: Bool { self == .asset || self == .liability }
}
