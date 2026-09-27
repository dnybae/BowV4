import Foundation

struct BudgetMoney {
  static func parseMinor(_ text: String) -> Int64? {
    let locale = Locale.current
    let grouping = locale.groupingSeparator ?? ","
    let decimalSeparator = locale.decimalSeparator ?? "."
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: grouping, with: "")
      .replacingOccurrences(of: decimalSeparator, with: ".")
    guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    else { return nil }
    let minor = decimal * 100
    guard minor == minor.rounded(0), minor <= Decimal(Int64.max),
          minor >= Decimal(Int64.min) else { return nil }
    return Int64(NSDecimalNumber(decimal: minor).stringValue)
  }

  static func formatted(_ minor: Int64, currencyCode: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    formatter.locale = .current
    let value = NSDecimalNumber(value: minor).dividing(by: NSDecimalNumber(value: 100))
    return formatter.string(from: value) ?? "\(minor / 100).\(abs(minor % 100))"
  }

  static func editable(_ minor: Int64) -> String {
    let value = Decimal(minor)
    let positive = value < 0 ? -value : value
    return NSDecimalNumber(decimal: positive)
      .dividing(by: NSDecimalNumber(value: 100))
      .stringValue
      .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
  }
}

private extension Decimal {
  func rounded(_ scale: Int) -> Decimal {
    var value = self
    var result = Decimal()
    NSDecimalRound(&result, &value, scale, .plain)
    return result
  }
}
