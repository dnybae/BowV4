import SwiftUI

/// A budget envelope row: name and signed available money, colored by funding status.
struct EnvelopeBudgetRow: View {
  var name: String
  var availableMinor: Int64
  var cashOverspentMinor: Int64
  var creditOverspentMinor: Int64
  var assignedMinor: Int64
  var activityMinor: Int64
  var monthlyTargetMinor: Int64?
  var currencyCode: String

  private var status: EnvelopeStatus {
    EnvelopeStatus(
      availableMinor: availableMinor, assignedMinor: assignedMinor,
      monthlyTargetMinor: monthlyTargetMinor, currencyCode: currencyCode
    )
  }

  /// Credit-only overspending adds card debt, so the pill carries a card.
  private var isCreditOverspending: Bool {
    availableMinor < 0 && creditOverspentMinor > 0 && cashOverspentMinor == 0
  }

  private var accessibilityStatus: String {
    let status = status
    let available = "\(status.availableText) available"
    let spent = BudgetMoney.formatted(max(0, -activityMinor), currencyCode: currencyCode)
    switch status.state {
    case .over:
      let over = BudgetMoney.formatted(-availableMinor, currencyCode: currencyCode)
      let explanation = isCreditOverspending ? "Over by \(over) on credit, adds debt"
        : cashOverspentMinor > 0 ? "Cash overspent by \(over)" : "Over by \(over)"
      return "\(available), \(explanation)"
    case .needs:
      return "\(available), \(status.detailText), spent \(spent)"
    case .funded, .empty:
      return "\(available), spent \(spent)"
    }
  }

  var body: some View {
    BudgetStatusRow(
      name: name, status: status,
      pillSymbol: isCreditOverspending ? "creditcard.fill" : nil,
      accessibilityStatus: accessibilityStatus
    )
  }
}
