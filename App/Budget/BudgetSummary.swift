import Foundation

struct BudgetSummary {
  var readyToAssignMinor: Int64
  var assignedThisMonthMinor: Int64
  var assignedInFutureMinor: Int64
  var overspentMinor: Int64
  /// Net spending out of budget envelopes this month; refunds reduce it.
  var spentThisMonthMinor: Int64
  /// Money still sitting in budget envelopes. Shortfalls are counted in `overspentMinor` instead.
  var availableMinor: Int64
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
    let budgetEnvelopes = envelopes.filter { $0.paymentAccountID == nil }
    overspentMinor = budgetEnvelopes.reduce(0) { total, envelope in
      total + max(0, -snapshot.available(for: envelope.id))
    }
    spentThisMonthMinor = max(0, budgetEnvelopes.reduce(0) { total, envelope in
      total - snapshot.activity[envelope.id, default: 0]
    })
    availableMinor = budgetEnvelopes.reduce(0) { total, envelope in
      total + max(0, snapshot.available(for: envelope.id))
    }
    let interval = calendar.dateInterval(of: .month, for: snapshot.month)
    assignedThisMonthMinor = BudgetMonthAccessPolicy(calendar: calendar)
      .assignedMinor(in: snapshot.month, funding: allocations.map(\.monthFundingItem))
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

extension BudgetSummary {
  /// Share of this month's cash that has a job: assigned ÷ (assigned + Ready to Assign), from 0 to 1.
  var assignedShare: Double {
    Self.assignedShare(assignedMinor: assignedThisMonthMinor, readyToAssignMinor: readyToAssignMinor)
  }

  static func assignedShare(assignedMinor: Int64, readyToAssignMinor: Int64) -> Double {
    let assigned = max(0, assignedMinor)
    let total = assigned + readyToAssignMinor
    guard total > 0 else { return assigned > 0 ? 1 : 0 }
    return min(1, max(0, Double(assigned) / Double(total)))
  }
}

extension BudgetAllocation {
  var monthFundingItem: BudgetMonthFundingItem {
    BudgetMonthFundingItem(
      date: date,
      amountMinor: amountMinor,
      hasSource: sourceEnvelopeID != nil || sourceCardID != nil,
      hasTarget: targetEnvelopeID != nil || targetCardID != nil
    )
  }
}
