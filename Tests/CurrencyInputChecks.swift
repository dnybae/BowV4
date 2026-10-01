import Foundation

@main
struct CurrencyInputChecks {
  static func main() {
    let negative: Int64 = -123_456_789
    let formatted = BudgetMoney.formatted(negative, currencyCode: "USD")
    precondition(formatted.contains("−") && !formatted.contains("-"))
    precondition(CurrencyInputEditor.pasted(formatted, into: 0, allowsNegative: true) == negative,
                 "Copying an app-formatted negative amount must preserve its sign")
    precondition(CurrencyInputEditor.pasted(formatted, into: 0, allowsNegative: false) == -negative)
    precondition(BudgetMoney.parseMinor("−1,234,567.89", locale: Locale(identifier: "en_US")) == negative)
    precondition(BudgetMoney.parseMinor("−1.234.567,89", locale: Locale(identifier: "de_DE")) == negative)
    precondition(CurrencyInputEditor.pasted("-123.45", into: 0, allowsNegative: true) == -12_345)
    precondition(CurrencyInputEditor.pasted("−0.01", into: 0, allowsNegative: true) == -1)
    let oversized = BudgetMoney.formatted(Int64.min, currencyCode: "USD")
    precondition(CurrencyInputEditor.pasted(oversized, into: 250, allowsNegative: false) == 250)
    precondition(CurrencyInputEditor.appending("125", to: 0) == 125)
    precondition(CurrencyInputEditor.deletingLastDigit(from: -125) == -12)
    print("Currency input checks passed")
  }
}
