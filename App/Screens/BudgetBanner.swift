import SwiftUI

/// A notification-style card on the Budget screen. Tone sets the icon, tint and edge;
/// each kind also has its own symbol so the meaning never depends on color alone.
struct BudgetBanner: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var notice: BudgetNotice
  var currencyCode: String

  private var ink: Color {
    switch notice.tone {
    case .brand: Bow.bowInk
    case .caution: Bow.needsInk
    case .critical: Bow.overInk
    }
  }

  private var tint: Color {
    switch notice.tone {
    case .brand: Bow.bowTint
    case .caution: Bow.needsTint
    case .critical: Bow.overTint
    }
  }

  private var accent: Color {
    switch notice.tone {
    case .brand: Bow.bow
    case .caution: Bow.needs
    case .critical: Bow.over
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: Bow.Space.s3) {
      // The icon is decorative; at accessibility sizes the text needs the width more.
      if !dynamicTypeSize.isAccessibilitySize {
        icon
      }
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        let titleLayout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
        titleLayout {
          MoneyText(minor: notice.amountMinor, currencyCode: currencyCode)
            .font(.bowAmount)
            .foregroundStyle(notice.tone == .brand ? Bow.ink : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(notice.title)
            .font(.bowHeadline)
            .foregroundStyle(Bow.ink)
        }
        Text(notice.message)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      if notice.isActionable {
        Image(systemName: "chevron.right")
          .font(.bowFootnote.weight(.semibold))
          .foregroundStyle(Bow.inkFaint)
          .frame(maxHeight: .infinity)
          .accessibilityHidden(true)
      }
    }
    .padding(Bow.Space.s4)
    .background(Bow.card, in: RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous)
        .strokeBorder(
          LinearGradient(colors: [accent.opacity(contrast == .increased ? 0.9 : 0.45), tint],
                         startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: contrast == .increased ? 2 : 1.5
        )
    )
    .shadow(color: accent.opacity(0.12), radius: 15, y: 10)
    .contentShape(RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var icon: some View {
    Image(systemName: notice.symbol)
      .bowScaledIcon(frame: 34, glyph: 16)
      .foregroundStyle(ink)
      .background(
        reduceTransparency
          ? AnyShapeStyle(tint)
          : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.9), tint], startPoint: .topLeading, endPoint: .bottomTrailing)),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
      .shadow(color: accent.opacity(0.3), radius: 6, y: 4)
      .accessibilityHidden(true)
  }
}
