import SwiftUI

/// A Budget screen row: status ring, name and a color-coded status pill. Nothing else.
/// Used for envelopes and card payments. At accessibility text sizes the pill moves under the name.
struct BudgetStatusRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var name: String
  var status: EnvelopeStatus
  /// A small symbol inside the pill, e.g. a card for credit overspending.
  var pillSymbol: String? = nil
  /// Spoken after the name. Carries the detail the row no longer shows as text.
  var accessibilityStatus: String

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s2))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s3))
    layout {
      HStack(spacing: Bow.Space.s3) {
        StatusRing(fraction: status.ringFraction, state: status.state)
        Text(name)
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: Bow.Space.s2)
      }
      StatusPill(text: status.pillText, state: status.state, symbol: pillSymbol)
    }
    .frame(minHeight: 44)
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name)
    .accessibilityValue(accessibilityStatus)
  }
}
