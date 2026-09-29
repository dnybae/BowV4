import Foundation

struct BudgetSummary {
  var readyToAssignMinor: Int64
  var assignedThisMonthMinor: Int64
  var assignedInFutureMinor: Int64
  var overspentMinor: Int64
  var creditOwedMinor: Int64
  var creditReservedMinor: Int64
  var creditUncoveredMinor: Int64

  init(
    snapshot: BudgetSnapshot,
    envelopes: [BudgetEnvelope],
    accounts: [BudgetAccount],
    allocations: [BudgetAllocation],
    calendar: Calendar = .current
  ) {
    readyToAssignMinor = snapshot.readyToAssignMinor
    assignedInFutureMinor = snapshot.assignedInFutureMinor
    overspentMinor = envelopes.filter { $0.paymentAccountID == nil }.reduce(0) { total, envelope in
      total + max(0, -snapshot.available(for: envelope.id))
    }
    let interval = calendar.dateInterval(of: .month, for: snapshot.month)
    assignedThisMonthMinor = allocations.reduce(0) { total, allocation in
      guard let interval, interval.contains(allocation.date) else { return total }
      let hasSource = allocation.sourceEnvelopeID != nil || allocation.sourceCardID != nil
      let hasTarget = allocation.targetEnvelopeID != nil || allocation.targetCardID != nil
      if !hasSource && hasTarget { return total + allocation.amountMinor }
      if hasSource && !hasTarget { return total - allocation.amountMinor }
      return total
    }
    let cards = accounts.filter { $0.kind == .credit && $0.openedAt < (interval?.end ?? .distantFuture) }
    creditOwedMinor = cards.reduce(0) { total, card in
      total + max(0, -snapshot.accountBalances[card.id, default: 0])
    }
    creditReservedMinor = cards.reduce(0) { total, card in
      total + max(0, snapshot.paymentAvailable[card.id, default: 0])
    }
    creditUncoveredMinor = cards.reduce(0) { total, card in
      let owed = max(0, -snapshot.accountBalances[card.id, default: 0])
      let reserved = max(0, snapshot.paymentAvailable[card.id, default: 0])
      return total + max(0, owed - reserved)
    }
  }
}
