import SwiftUI

/// One native list row replacing a collapsed group's items. Its total stays neutral,
/// while the supporting line explains the items' states.
struct BowGroupSummaryRow<Detail: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var count: Text
  var totalMinor: Int64
  var totalLabel: String
  var currencyCode: String
  @ViewBuilder var detail: () -> Detail

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s2))
      : AnyLayout(HStackLayout(alignment: .top, spacing: Bow.Space.s3))
    layout {
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        count
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
        detail()
          .font(.bowSubhead)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
        MoneyText(minor: totalMinor, currencyCode: currencyCode)
          .font(.bowAmount)
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(totalLabel)
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
      }
      .layoutPriority(1)
      .accessibilityElement(children: .combine)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .padding(.vertical, Bow.Space.s1)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Expands the group")
  }
}
