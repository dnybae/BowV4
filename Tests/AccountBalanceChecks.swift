import Foundation

@main
struct AccountBalanceChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func date(_ day: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }
    func account(_ kind: BudgetAccountKind, _ opening: Int64, currency: String = "USD") -> AccountLedgerItem {
      AccountLedgerItem(id: UUID(), kind: kind, openingBalanceMinor: opening,
                        openedAt: date(1), currencyCode: currency)
    }
    func transaction(_ amount: Int64, from source: UUID, to destination: UUID? = nil,
                     on day: Int) -> TransactionLedgerItem {
      TransactionLedgerItem(
        id: UUID(), date: date(day), createdAt: date(day), amountMinor: amount,
        accountID: source, transferAccountID: destination, envelopeID: nil,
        kind: destination == nil ? (amount >= 0 ? .inflow : .expense) : .transfer
      )
    }
    let cash = account(.cash, 100_000)
    let asset = account(.asset, 500_000)
    let card = account(.credit, -20_000)
    let loan = account(.liability, -150_000)
    let accounts = [cash, asset, card, loan]
    let calculator = AccountBalanceCalculator()
    let starting = calculator.calculate(before: date(2), accounts: accounts, transactions: [],
                                        reportingCurrencyCode: "USD")
    expect(starting.netWorthMinor == 430_000, "all assets and signed debts contribute exactly")

    let expense = transaction(-5_000, from: cash.id, on: 3)
    let loanPayment = transaction(-10_000, from: cash.id, to: loan.id, on: 4)
    let cardPayment = transaction(-2_000, from: cash.id, to: card.id, on: 5)
    let valuation = transaction(100_000, from: asset.id, on: 20)
    let entries = [expense, loanPayment, cardPayment, valuation]
    let beforeValuation = calculator.calculate(before: date(20), accounts: accounts,
                                               transactions: entries, reportingCurrencyCode: "USD")
    expect(beforeValuation.netWorthMinor == 425_000,
           "expenses reduce net worth while internal transfers preserve it")
    let afterValuation = calculator.calculate(before: date(21), accounts: accounts,
                                              transactions: entries, reportingCurrencyCode: "USD")
    expect(afterValuation.netWorthMinor == 525_000,
           "a dated asset valuation affects later history only")
    expect(afterValuation.balances[loan.id] == -140_000, "loan payment reduces signed debt")
    expect(afterValuation.balances[card.id] == -18_000, "card payment reduces signed debt")

    let future = transaction(-7_000, from: cash.id, on: 25)
    let current = calculator.calculate(before: date(24), inclusive: true, accounts: accounts,
                                       transactions: entries + [future], reportingCurrencyCode: "USD")
    expect(current.netWorthMinor == 525_000, "future-dated entries are excluded from today's value")

    let overpaidCard = account(.credit, 2_500)
    let credit = calculator.calculate(before: date(2), accounts: [overpaidCard], transactions: [],
                                      reportingCurrencyCode: "USD")
    expect(credit.netWorthMinor == 2_500, "a positive card balance is an asset")

    let positiveLoan = account(.liability, 1_000)
    expect(calculator.calculate(before: date(2), accounts: [positiveLoan], transactions: [])
      .netWorthMinor == nil, "ambiguous positive loan balance cannot produce a total")
    let euro = account(.asset, 1_000, currency: "EUR")
    expect(calculator.calculate(before: date(2), accounts: [cash, euro], transactions: [],
                                reportingCurrencyCode: "USD").netWorthMinor == nil,
           "unconverted currencies cannot be added")
    let missingDestination = transaction(-1_000, from: cash.id, to: UUID(), on: 4)
    expect(calculator.calculate(before: date(5), accounts: [cash],
                                transactions: [missingDestination]).netWorthMinor == nil,
           "orphaned transfers cannot produce a misleading total")

    print("Account balance checks passed")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
