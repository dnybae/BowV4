import SwiftUI

/// A notification-style card on the Budget screen. Tone sets the icon, tint and edge;
/// each kind also has its own symbol so the meaning never depends on color alone.
/// Ready to Assign is the screen's focal point, so it's filled with the brand color and
/// carries a small ring showing how much of this month's cash already has a job.
struct BudgetBanner: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var notice: BudgetNotice
  var currencyCode: String
  /// Share of this month's cash that's assigned, for the Ready to Assign ring.
  var assignedShare: Double? = nil

  private var isFilled: Bool { notice.tone == .brand }

  private var ink: Color {
    switch notice.tone {
    case .brand: Bow.onBow
    case .caution: Bow.needsInk
    case .critical: Bow.overInk
    }
  }

  private var tint: Color {
    switch notice.tone {
    case .brand: Bow.bowSolid
    case .caution: Bow.needsTint
    case .critical: Bow.overTint
    }
  }

  private var accent: Color {
    switch notice.tone {
    case .brand: Bow.bowSolid
    case .caution: Bow.needs
    case .critical: Bow.over
    }
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous)
  }

  var body: some View {
    HStack(alignment: .top, spacing: Bow.Space.s3) {
      // The icon is decorative; at accessibility sizes the text needs the width more.
      if !dynamicTypeSize.isAccessibilitySize {
        if isFilled, let assignedShare {
          AssignedRing(fraction: assignedShare, symbol: notice.symbol)
        } else {
          icon
        }
      }
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        let titleLayout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
        titleLayout {
          MoneyText(minor: notice.amountMinor, currencyCode: currencyCode)
            .font(isFilled ? .bowTitle : .bowAmount)
            .foregroundStyle(isFilled ? Bow.onBow : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(notice.title)
            .font(.bowHeadline)
            .foregroundStyle(isFilled ? Bow.onBow : Bow.ink)
        }
        Text(notice.message)
          .font(.bowSubhead)
          .foregroundStyle(isFilled ? Bow.onBow.opacity(0.85) : Bow.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      if notice.isActionable {
        Image(systemName: "chevron.right")
          .font(.bowFootnote.weight(.semibold))
          .foregroundStyle(isFilled ? Bow.onBow.opacity(0.7) : Bow.inkFaint)
          .frame(maxHeight: .infinity)
          .accessibilityHidden(true)
      }
    }
    .padding(Bow.Space.s4)
    .background(isFilled ? tint : Bow.card, in: shape)
    .overlay {
      if !isFilled {
        shape.strokeBorder(accent.opacity(contrast == .increased ? 0.9 : 0.45),
                           lineWidth: contrast == .increased ? 2 : 1.5)
      }
    }
    .contentShape(shape)
    .accessibilityElement(children: .combine)
    .accessibilityValue(assignedShare.map { "\(Int(($0 * 100).rounded())) percent of this month’s money assigned" } ?? "")
  }

  private var icon: some View {
    Image(systemName: notice.symbol)
      .bowScaledIcon(frame: 34, glyph: 16)
      .foregroundStyle(ink)
      .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// The small ring on the Ready to Assign banner: how much of this month's cash has a job.
/// It sweeps as money is assigned.
private struct AssignedRing: View {
  var fraction: Double
  var symbol: String
  @ScaledMetric private var scale: CGFloat = 1

  var body: some View {
    let side = 40 * min(scale, Bow.maxGraphicScale)
    ZStack {
      Circle().stroke(Bow.onBow.opacity(0.28), lineWidth: 4)
      Circle().trim(from: 0, to: fraction)
        .stroke(Bow.onBow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Image(systemName: symbol)
        .font(.system(size: side * 0.36, weight: .semibold))
        .foregroundStyle(Bow.onBow)
    }
    .frame(width: side, height: side)
    .bowAnimation(Bow.ringMotion, value: fraction)
    .accessibilityHidden(true)
  }
}
