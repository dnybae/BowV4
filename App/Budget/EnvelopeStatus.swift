import Foundation

/// Available money and status for rows, with funding explanations for details.
/// Presentation only; every input comes from the budget snapshot.
struct EnvelopeStatus {
  var state: EnvelopeState
  var availableText: String
  var detailText: String
  var fundingProgress: EnvelopeFundingProgress? = nil
  /// Card payment details show money set aside against what's owed.
  var paymentFundingFraction: Double = 0

  init(availableMinor: Int64, assignedMinor: Int64,
       monthlyTargetMinor: Int64?, currencyCode: String) {
    availableText = BudgetMoney.formatted(availableMinor, currencyCode: currencyCode)
    fundingProgress = EnvelopeFundingProgress(assignedMinor: assignedMinor, targetMinor: monthlyTargetMinor)
    if availableMinor < 0 {
      state = .over
      detailText = "Over \(BudgetMoney.formatted(-availableMinor, currencyCode: currencyCode))"
    } else if let fundingProgress, !fundingProgress.isFullyFunded {
      state = .needs
      detailText = "Needs \(BudgetMoney.formatted(fundingProgress.remainingMinor, currencyCode: currencyCode))"
    } else if availableMinor > 0 {
      state = .funded
      detailText = availableText
    } else {
      state = .empty
      detailText = availableText
    }
  }

  /// Card payments: rows show payment money set aside, details explain any shortfall.
  /// Debt carried in from an earlier month is short (over); new credit spending this month still needs funding.
  init(cardOwedMinor owed: Int64, reservedMinor reserved: Int64, isCarryingDebt: Bool, currencyCode: String) {
    availableText = BudgetMoney.formatted(reserved, currencyCode: currencyCode)
    if owed > reserved {
      let shortfall = BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)
      state = isCarryingDebt ? .over : .needs
      paymentFundingFraction = Self.fraction(reserved, of: owed)
      detailText = isCarryingDebt ? "Short \(shortfall)" : "Needs \(shortfall)"
    } else if reserved > 0 {
      state = .funded
      paymentFundingFraction = 1
      detailText = availableText
    } else {
      state = .empty
      detailText = availableText
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
