import Foundation

@MainActor
@main
struct EnvelopePresentationChecks {
  static func main() {
    let travel = envelope(available: 35_000, assigned: 35_000, target: 50_000)
    expect(travel.availableText == money(35_000), "underfunded rows show spendable money, not the funding gap")
    expect(travel.state == .needs && travel.detailText == "Needs \(money(15_000))",
           "the funding gap remains available to details and accessibility")
    expect(travel.fundingProgress?.fraction == 0.7, "funding uses assigned money against the target")

    let zeroUnderfunded = envelope(available: 0, assigned: 0, target: 50_000)
    expect(zeroUnderfunded.availableText == money(0) && zeroUnderfunded.state == .needs,
           "zero availability retains the underfunded warning")

    let fullyFunded = envelope(available: 50_000, assigned: 50_000, target: 50_000)
    let afterSpending = envelope(available: 20_000, assigned: 50_000, target: 50_000)
    let spentInFull = envelope(available: 0, assigned: 50_000, target: 50_000)
    let overspent = envelope(available: -5_800, assigned: 50_000, target: 50_000)
    for status in [fullyFunded, afterSpending, spentInFull, overspent] {
      expect(status.fundingProgress?.fraction == 1 && status.fundingProgress?.remainingMinor == 0,
             "spending and overspending never erase a fully funded target")
    }
    expect(afterSpending.availableText == money(20_000), "spending changes the available amount")
    expect(spentInFull.state == .empty, "a spent target has zero available without a new funding warning")
    expect(overspent.availableText == money(-5_800) && overspent.state == .over,
           "overspent rows retain the negative balance and overspending color")

    let partiallyFundedOverspent = envelope(available: -2_000, assigned: 20_000, target: 50_000)
    expect(partiallyFundedOverspent.state == .over && partiallyFundedOverspent.fundingProgress?.fraction == 0.4,
           "overspending takes warning priority while target funding keeps its own meaning")

    let missingTargets: [Int64?] = [nil, 0, -1]
    for target in missingTargets {
      expect(envelope(available: 10_000, assigned: 10_000, target: target).fundingProgress == nil,
             "envelopes without a positive target have no progress bar")
    }
    let movedOut = envelope(available: 0, assigned: -10_000, target: 50_000)
    expect(movedOut.fundingProgress?.fraction == 0 && movedOut.fundingProgress?.remainingMinor == 50_000,
           "moving money out cannot create negative progress")
    let overfunded = envelope(available: 60_000, assigned: 60_000, target: 50_000)
    expect(overfunded.fundingProgress?.fraction == 1 && overfunded.fundingProgress?.assignedMinor == 60_000,
           "overfunding caps the bar while preserving the actual funded amount")

    for carryingDebt in [false, true] {
      let card = EnvelopeStatus(cardOwedMinor: 50_000, reservedMinor: 20_000,
                                isCarryingDebt: carryingDebt, currencyCode: "USD")
      expect(card.availableText == money(20_000), "card rows show money available for payment")
      expect(card.paymentFundingFraction == 0.4 && card.fundingProgress == nil,
             "card payoff coverage stays independent from envelope target funding")
      expect(card.state == (carryingDebt ? .over : .needs), "card shortfall classification is preserved")
      expect(card.detailText == "\(carryingDebt ? "Short" : "Needs") \(money(30_000))",
             "card details still explain the payment shortfall")
    }
    let paidCard = EnvelopeStatus(cardOwedMinor: 0, reservedMinor: 0,
                                 isCarryingDebt: false, currencyCode: "USD")
    expect(paidCard.availableText == money(0) && paidCard.paymentFundingFraction == 0,
           "empty card payments have a finite zero amount and coverage")
    print("Envelope presentation checks passed")
  }

  private static func envelope(available: Int64, assigned: Int64, target: Int64?) -> EnvelopeStatus {
    EnvelopeStatus(availableMinor: available, assignedMinor: assigned,
                   monthlyTargetMinor: target, currencyCode: "USD")
  }

  private static func money(_ minor: Int64) -> String {
    BudgetMoney.formatted(minor, currencyCode: "USD")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
