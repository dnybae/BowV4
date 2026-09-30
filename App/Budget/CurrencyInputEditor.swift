import Foundation

/// Right-to-left currency entry: each digit shifts existing digits one place left.
struct CurrencyInputEditor {
  static let maximumDigits = 12

  static func appending(_ digits: String, to minor: Int64) -> Int64 {
    var magnitude = minor.magnitude
    for character in digits {
      guard let digit = character.wholeNumberValue else { continue }
      guard String(magnitude).count < maximumDigits || magnitude == 0 else { break }
      magnitude = magnitude * 10 + UInt64(digit)
    }
    let value = Int64(magnitude)
    return minor < 0 ? -value : value
  }

  static func deletingLastDigit(from minor: Int64) -> Int64 {
    minor / 10
  }

  static func pasted(_ text: String, into minor: Int64, allowsNegative: Bool) -> Int64 {
    let symbols = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".,-"))
    let cleaned = String(text.unicodeScalars.filter(symbols.contains))
    guard var parsed = BudgetMoney.parseMinor(cleaned) else { return appending(text, to: minor) }
    if !allowsNegative { parsed = abs(parsed) }
    return String(parsed.magnitude).count <= maximumDigits ? parsed : minor
  }
}
