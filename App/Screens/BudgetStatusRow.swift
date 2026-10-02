import SwiftUI

/// A Budget screen row: status ring, name and a color-coded status pill. Nothing else.
/// Used for envelopes and card payments. Always one line: a name too long for the row fades
/// out at its end. At accessibility text sizes the pill moves under the name.
struct BudgetStatusRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var name: String
  var status: EnvelopeStatus
  /// A small symbol inside the pill, e.g. a card for credit overspending.
  var pillSymbol: String? = nil
  /// Spoken after the name. Carries the detail the row no longer shows as text.
  var accessibilityStatus: String

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Bow.Space.s2) {
          HStack(spacing: Bow.Space.s3) {
            ring
            nameText
          }
          pill
        }
      } else {
        // One line: the pill keeps its full amount and a long name fades out before it.
        HStack(spacing: Bow.Space.s3) {
          ring
          nameText
            .fadingTail()
            .frame(maxWidth: .infinity, alignment: .leading)
          pill.layoutPriority(1)
        }
      }
    }
    .frame(minHeight: 44)
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name)
    .accessibilityValue(accessibilityStatus)
  }

  private var ring: some View {
    StatusRing(fraction: status.ringFraction, state: status.state)
  }

  private var nameText: some View {
    Text(name)
      .font(.bowHeadline)
      .foregroundStyle(Bow.ink)
  }

  private var pill: some View {
    StatusPill(text: status.pillText, state: status.state, symbol: pillSymbol)
  }
}
