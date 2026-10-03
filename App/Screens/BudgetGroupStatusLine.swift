import SwiftUI

/// Show problems first, without suggesting that a mixed group has one overall status.
struct BudgetGroupStatusLine: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var summary: BudgetGroupSummary
  var isCardPayments = false

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s1))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s1))
    layout {
      if summary.needsAttention {
        if summary.overspentCount > 0 {
          Text("\(summary.overspentCount) \(isCardPayments ? "short" : "overspent")")
            .foregroundStyle(Bow.overInk)
        }
        if summary.overspentCount > 0 && summary.needsFundingCount > 0 && !dynamicTypeSize.isAccessibilitySize {
          Text("·")
            .foregroundStyle(Bow.inkSoft)
            .accessibilityHidden(true)
        }
        if summary.needsFundingCount > 0 {
          Text(summary.needsFundingCount == 1 ? "1 needs funding" : "\(summary.needsFundingCount) need funding")
            .foregroundStyle(Bow.needsInk)
        }
      } else if summary.fundedCount > 0 {
        Text("Funded")
          .foregroundStyle(Bow.fundedInk)
      } else {
        Text("Empty")
          .foregroundStyle(Bow.inkSoft)
      }
    }
    .multilineTextAlignment(.leading)
    .accessibilityElement(children: .combine)
  }
}
