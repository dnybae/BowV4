import SwiftUI

/// A money amount that rolls its digits up or down when the value changes.
/// Rounded, with monospaced digits so columns don't jitter. The caller sets font, weight and color.
struct MoneyText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var minor: Int64
  var currencyCode: String
  /// Prefix positive amounts with "+", for money coming in.
  var showsPlusSign = false
  /// Show negatives with a true minus (−) instead of a hyphen, for hero amounts.
  var usesTrueMinus = false

  var body: some View {
    Text(text)
      .fontDesign(.rounded)
      .monospacedDigit()
      .contentTransition(reduceMotion ? .identity : .numericText(value: Double(minor)))
      .bowAnimation(value: minor)
      // A currency change is a different number, not a new value to roll to.
      .id(currencyCode)
  }

  private var text: String {
    let formatted = BudgetMoney.formatted(minor, currencyCode: currencyCode, showsPlusSign: showsPlusSign)
    return usesTrueMinus ? formatted.replacingOccurrences(of: "-", with: "\u{2212}") : formatted
  }
}
