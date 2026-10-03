import Foundation

/// How an envelope or card payment reads at a glance: its status family, row ring and pill text.
/// Presentation only; every input comes from the budget snapshot.
struct EnvelopeStatus {
  var state: EnvelopeState
  /// 0...1. Funded: share of the envelope's money still unspent. Needs: share of the target assigned.
  var ringFraction: Double
  var pillText: String

  init(availableMinor: Int64, assignedMinor: Int64, activityMinor: Int64,
       monthlyTargetMinor: Int64?, currencyCode: String) {
    let remainingTarget = monthlyTargetMinor.map { max(0, $0 - max(0, assignedMinor)) } ?? 0
    if availableMinor < 0 {
      state = .over
      ringFraction = 1
      pillText = "Over \(BudgetMoney.formatted(-availableMinor, currencyCode: currencyCode))"
    } else if remainingTarget > 0, let target = monthlyTargetMinor {
      state = .needs
      ringFraction = Self.fraction(max(0, assignedMinor), of: target)
      pillText = "Needs \(BudgetMoney.formatted(remainingTarget, currencyCode: currencyCode))"
    } else if availableMinor > 0 {
      let spent = max(0, -activityMinor)
      state = .funded
      ringFraction = Self.fraction(availableMinor, of: availableMinor + spent)
      pillText = BudgetMoney.formatted(availableMinor, currencyCode: currencyCode)
    } else {
      state = .empty
      ringFraction = 0
      pillText = BudgetMoney.formatted(0, currencyCode: currencyCode)
    }
  }

  /// Card payments: the ring shows payment money set aside against what's owed.
  /// Debt carried in from an earlier month is short (over); new credit spending this month still needs funding.
  init(cardOwedMinor owed: Int64, reservedMinor reserved: Int64, isCarryingDebt: Bool, currencyCode: String) {
    if owed > reserved {
      let shortfall = BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)
      state = isCarryingDebt ? .over : .needs
      ringFraction = Self.fraction(reserved, of: owed)
      pillText = isCarryingDebt ? "Short \(shortfall)" : "Needs \(shortfall)"
    } else if reserved > 0 {
      state = .funded
      ringFraction = 1
      pillText = BudgetMoney.formatted(reserved, currencyCode: currencyCode)
    } else {
      state = .empty
      ringFraction = 0
      pillText = BudgetMoney.formatted(0, currencyCode: currencyCode)
    }
  }

  /// Use the same debt classification for a card's row and its collapsed group.
  init(card: BudgetAccount, snapshot: BudgetSnapshot, previousSnapshot: BudgetSnapshot?, currencyCode: String) {
    let previousOwed = max(0, -(previousSnapshot?.accountBalances[card.id] ?? 0))
    let previousReserved = max(0, previousSnapshot?.paymentAvailable[card.id] ?? 0)
    self.init(
      cardOwedMinor: max(0, -snapshot.accountBalances[card.id, default: 0]),
      reservedMinor: max(0, snapshot.paymentAvailable[card.id, default: 0]),
      isCarryingDebt: previousOwed > previousReserved, currencyCode: currencyCode
    )
  }

  private static func fraction(_ part: Int64, of whole: Int64) -> Double {
    guard whole > 0 else { return 0 }
    return min(1, max(0, Double(part) / Double(whole)))
  }
}
