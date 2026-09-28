import Foundation

@main
struct BudgetCalculatorChecks {
  static func main() {
    let decimalSeparator = Locale.current.decimalSeparator ?? "."
    expect(BudgetMoney.parseMinor("12\(decimalSeparator)34") == 1_234, "money uses exact minor units")
    expect(BudgetMoney.parseMinor("-3\(decimalSeparator)25") == -325, "negative opening balance parses")
    expect(BudgetMoney.parseMinor(BudgetMoney.editableSigned(-325)) == -325,
           "editing a debt balance preserves its sign")
    expect(BudgetMoney.parseMinor("12\(decimalSeparator)345") == nil, "fractional cents are rejected")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let calculator = BudgetCalculator(calendar: calendar)
    func day(_ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    func allocation(_ amount: Int64, from source: BudgetBucket, to target: BudgetBucket) -> AllocationLedgerItem {
      AllocationLedgerItem(
        id: UUID(),
        date: day(1, 1),
        createdAt: day(1, 1),
        amountMinor: amount,
        source: source,
        target: target
      )
    }
    func transaction(
      _ amount: Int64,
      accountID: UUID,
      envelopeID: UUID?,
      kind: BudgetTransactionKind = .expense,
      destinationID: UUID? = nil
    ) -> TransactionLedgerItem {
      TransactionLedgerItem(
        id: UUID(),
        date: day(1, 5),
        createdAt: day(1, 5),
        amountMinor: amount,
        accountID: accountID,
        transferAccountID: destinationID,
        envelopeID: envelopeID,
        kind: kind
      )
    }

    let cashID = UUID()
    let cardID = UUID()
    let assetID = UUID()
    let groceriesID = UUID()
    let diningID = UUID()
    let cash = AccountLedgerItem(id: cashID, kind: .cash, openingBalanceMinor: 10_000, openedAt: day(1, 1))
    let card = AccountLedgerItem(id: cardID, kind: .credit, openingBalanceMinor: 0, openedAt: day(1, 1))
    let asset = AccountLedgerItem(id: assetID, kind: .asset, openingBalanceMinor: 0, openedAt: day(1, 1))
    let envelopes = [EnvelopeLedgerItem(id: groceriesID), EnvelopeLedgerItem(id: diningID)]
    let startingAllocations = [
      allocation(2_000, from: .readyToAssign, to: .envelope(groceriesID)),
      allocation(8_000, from: .readyToAssign, to: .envelope(diningID))
    ]

    let cashOverspend = transaction(-5_000, accountID: cashID, envelopeID: groceriesID)
    let cashSnapshot = calculator.calculate(
      month: day(1, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cashOverspend]
    )
    expect(cashSnapshot.cashTotalMinor == 5_000, "cash balance reflects posted expense")
    expect(cashSnapshot.available(for: groceriesID) == -3_000, "cash envelope shows overspending")
    expect(cashSnapshot.readyToAssignMinor == -3_000, "cash shortfall cannot inflate ready money")
    expect(
      cashSnapshot.cashTotalMinor
        == cashSnapshot.readyToAssignMinor
          + cashSnapshot.cashAvailable.values.reduce(0, +)
          + cashSnapshot.paymentAvailable.values.reduce(0, +),
      "cash-backed accounting identity"
    )

    let nextMonth = calculator.calculate(
      month: day(2, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cashOverspend]
    )
    expect(nextMonth.available(for: groceriesID) == 0, "cash shortfall does not roll into category")
    expect(nextMonth.readyToAssignMinor == -3_000, "uncovered cash shortfall remains in ready money")

    var releaseToReady = allocation(3_000, from: .envelope(diningID), to: .readyToAssign)
    releaseToReady.date = day(2, 2)
    let nextMonthCovered = calculator.calculate(
      month: day(2, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: startingAllocations + [releaseToReady],
      transactions: [cashOverspend]
    )
    expect(nextMonthCovered.readyToAssignMinor == 0, "returning funds clears carried ready deficit")
    expect(nextMonthCovered.available(for: diningID) == 5_000, "deficit cover uses real envelope funds")
    expect(nextMonthCovered.assigned[diningID] == -3_000, "release counts as negative assignment")

    let partlyAssigned = calculator.calculate(
      month: day(1, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: [startingAllocations[0]],
      transactions: [cashOverspend]
    )
    expect(partlyAssigned.readyToAssignMinor == 5_000, "ready money never exceeds cash on hand")

    let coverFromDining = allocation(3_000, from: .envelope(diningID), to: .envelope(groceriesID))
    let coveredCash = calculator.calculate(
      month: day(1, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: startingAllocations + [coverFromDining],
      transactions: [cashOverspend]
    )
    expect(coveredCash.available(for: groceriesID) == 0, "move covers cash overspending")
    expect(coveredCash.available(for: diningID) == 5_000, "source envelope pays for cover")
    expect(coveredCash.readyToAssignMinor == 0, "cover resolves negative ready money")

    let cardPurchase = transaction(-5_000, accountID: cardID, envelopeID: groceriesID)
    let creditSnapshot = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cardPurchase]
    )
    expect(creditSnapshot.available(for: groceriesID) == -3_000, "unfunded card spending is visible")
    expect(creditSnapshot.paymentAvailable[cardID] == 2_000, "only funded spending reserves payment cash")
    expect(creditSnapshot.readyToAssignMinor == 0, "card debt cannot become ready money")
    expect(creditSnapshot.accountBalances[cardID] == -5_000, "card liability includes full charge")

    let coveredCredit = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations + [coverFromDining],
      transactions: [cardPurchase]
    )
    expect(coveredCredit.paymentAvailable[cardID] == 5_000, "cover reserves the full payment")
    expect(coveredCredit.available(for: diningID) == 5_000, "cover reduces source funds")
    expect(coveredCredit.readyToAssignMinor == 0, "cover does not create cash")

    var laterCover = coverFromDining
    laterCover.date = day(1, 6)
    let coveredAfterPurchase = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations + [laterCover],
      transactions: [cardPurchase]
    )
    expect(coveredAfterPurchase.paymentAvailable[cardID] == 5_000, "later cover funds the card payment")
    expect(coveredAfterPurchase.available(for: groceriesID) == 0, "later cover clears card shortfall")

    var cardPayment = transaction(
      -2_000,
      accountID: cashID,
      envelopeID: nil,
      kind: .transfer,
      destinationID: cardID
    )
    cardPayment.date = day(1, 6)
    let afterPayment = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cardPurchase, cardPayment]
    )
    expect(afterPayment.cashTotalMinor == 8_000, "payment leaves cash")
    expect(afterPayment.accountBalances[cardID] == -3_000, "payment reduces card debt")
    expect(afterPayment.paymentAvailable[cardID] == 0, "payment spends the reserve")
    expect(afterPayment.readyToAssignMinor == 0, "payment does not change ready money")

    var oversizedPayment = transaction(
      -3_000,
      accountID: cashID,
      envelopeID: nil,
      kind: .transfer,
      destinationID: cardID
    )
    oversizedPayment.date = day(1, 6)
    let afterOversizedPayment = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cardPurchase, oversizedPayment]
    )
    expect(afterOversizedPayment.paymentAvailable[cardID] == 0, "payment reserve cannot be negative")
    expect(afterOversizedPayment.readyToAssignMinor == -1_000, "unfunded payment reduces ready money")

    var refund = transaction(
      1_000,
      accountID: cardID,
      envelopeID: groceriesID,
      kind: .inflow
    )
    refund.date = day(1, 6)
    let afterRefund = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, card],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [cardPurchase, refund]
    )
    expect(afterRefund.available(for: groceriesID) == -2_000, "card refund reduces unfunded spend")
    expect(afterRefund.paymentAvailable[cardID] == 2_000, "refund of unfunded spend leaves reserve")
    expect(afterRefund.readyToAssignMinor == 0, "card refund does not mint cash")

    let uncategorized = calculator.calculate(
      month: day(1, 15),
      accounts: [cash],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [transaction(-500, accountID: cashID, envelopeID: nil)]
    )
    expect(uncategorized.readyToAssignMinor == -500, "uncategorized cash outflow reduces ready money")

    let trackingTransfer = transaction(
      -1_000,
      accountID: cashID,
      envelopeID: groceriesID,
      kind: .transfer,
      destinationID: assetID
    )
    let trackingSnapshot = calculator.calculate(
      month: day(1, 15),
      accounts: [cash, asset],
      envelopes: envelopes,
      allocations: startingAllocations,
      transactions: [trackingTransfer]
    )
    expect(trackingSnapshot.available(for: groceriesID) == 1_000, "tracking transfer spends funded envelope")
    expect(trackingSnapshot.netWorthMinor == 10_000, "tracking transfer preserves net worth")
    expect(trackingSnapshot.readyToAssignMinor == 0, "tracking transfer cannot fund another envelope")

    print("Budget calculator checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
