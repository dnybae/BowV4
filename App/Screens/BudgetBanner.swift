import SwiftUI

/// A notification-style card on the Budget screen. Ready to Assign and warnings share one
/// layout, since they matter equally: a tinted icon tile, the amount and title on one line,
/// and a chevron. Tone sets the colors, matching the envelope pills (green for money waiting,
/// red for overspending); each kind also has its own symbol so meaning never depends on color.
struct BudgetBanner: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var notice: BudgetNotice
  var currencyCode: String

  private var ink: Color {
    switch notice.tone {
    case .positive: Bow.fundedInk
    case .critical: Bow.overInk
    }
  }

  private var tint: Color {
    switch notice.tone {
    case .positive: Bow.fundedTint
    case .critical: Bow.overTint
    }
  }

  private var accent: Color {
    switch notice.tone {
    case .positive: Bow.funded
    case .critical: Bow.over
    }
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous)
  }

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      // The icon is decorative; at accessibility sizes the text needs the width more.
      if !dynamicTypeSize.isAccessibilitySize {
        icon
      }
      // One line: amount on the left, title against the right edge. The amount keeps its full
      // width first and the title fades out if it's cut. At accessibility sizes they stack instead.
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 0) {
          amount
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          title
        }
        Spacer(minLength: 0)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: Bow.Space.s2) {
          amount.fadingTail().layoutPriority(1)
          Spacer(minLength: 0)
          title.fadingTail()
        }
      }
      if notice.isActionable {
        Image(systemName: "chevron.right")
          .font(.bowFootnote.weight(.semibold))
          .foregroundStyle(ink.opacity(0.7))
          .accessibilityHidden(true)
      }
    }
    .padding(Bow.Space.s4)
    .background(tint, in: shape)
    .overlay {
      shape.strokeBorder(accent.opacity(contrast == .increased ? 0.9 : 0.3),
                         lineWidth: contrast == .increased ? 2 : 1.5)
    }
    .contentShape(shape)
    .accessibilityElement(children: .combine)
    // The explanation no longer shows on screen, but VoiceOver still reads it.
    .accessibilityValue(notice.message)
  }

  private var amount: some View {
    MoneyText(minor: notice.amountMinor, currencyCode: currencyCode)
      .font(.bowAmount)
      .foregroundStyle(ink)
  }

  private var title: some View {
    Text(notice.title)
      .font(.bowHeadline)
      .foregroundStyle(Bow.ink)
  }

  private var icon: some View {
    Image(systemName: notice.symbol)
      .bowScaledIcon(frame: 34, glyph: 16)
      .foregroundStyle(ink)
      .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      .accessibilityHidden(true)
  }
}
