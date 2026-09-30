import Foundation

struct BudgetMoney {
  static func parseMinor(_ text: String) -> Int64? {
    parseMinor(text, locale: .current)
  }

  static func parseMinor(_ text: String, locale: Locale) -> Int64? {
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
    (Decimal(minor) / 100).formatted(.currency(code: currencyCode))
  }

  /// Formats a decimal string reported by a bank, such as "-1234.50".
  static func formatted(bankAmount: String, currencyCode: String) -> String {
    parseMinor(bankAmount, locale: Locale(identifier: "en_US_POSIX"))
      .map { formatted($0, currencyCode: currencyCode) } ?? bankAmount
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
