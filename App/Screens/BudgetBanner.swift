import SwiftUI

/// A notification-style card on the Budget screen. Tone sets the icon, tint and edge;
/// each kind also has its own symbol so the meaning never depends on color alone.
/// Ready to Assign is the screen's focal point: green like a funded envelope's pill, larger,
/// and just the amount with a small ring showing how much of this month's cash has a job.
/// Overspending gets the same solid tint in red, matching an overspent envelope's pill.
struct BudgetBanner: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var notice: BudgetNotice
  var currencyCode: String
  /// Share of this month's cash that's assigned, for the Ready to Assign ring.
  var assignedShare: Double? = nil

  /// Ready to Assign shows only its amount; warnings also explain what to do.
  private var isHero: Bool { notice.tone == .positive }

  /// Ready to Assign and overspending sit on a solid tint; other warnings use a plain card.
  private var isFilled: Bool { notice.tone != .caution }

  private var ink: Color {
    switch notice.tone {
    case .positive: Bow.fundedInk
    case .caution: Bow.needsInk
    case .critical: Bow.overInk
    }
  }

  private var tint: Color {
    switch notice.tone {
    case .positive: Bow.fundedTint
    case .caution: Bow.needsTint
    case .critical: Bow.overTint
    }
  }

  private var accent: Color {
    switch notice.tone {
    case .positive: Bow.funded
    case .caution: Bow.needs
    case .critical: Bow.over
    }
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous)
  }

  var body: some View {
    HStack(alignment: isHero ? .center : .top, spacing: Bow.Space.s3) {
      // The icon is decorative; at accessibility sizes the text needs the width more.
      if !dynamicTypeSize.isAccessibilitySize {
        if isHero, let assignedShare {
          AssignedRing(fraction: assignedShare, symbol: notice.symbol)
        } else {
          icon
        }
      }
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        // Amount and title share a line when they fit; on narrow phones the title wraps below.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            amount
            title.lineLimit(1)
          }
          VStack(alignment: .leading, spacing: 0) {
            amount
            title
          }
        }
        if !isHero {
          Text(notice.message)
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      if notice.isActionable {
        Image(systemName: "chevron.right")
          .font(.bowFootnote.weight(.semibold))
          .foregroundStyle(isFilled ? ink.opacity(0.7) : Bow.inkFaint)
          .frame(maxHeight: isHero ? nil : .infinity)
          .accessibilityHidden(true)
      }
    }
    .padding(Bow.Space.s4)
    .background(isFilled ? tint : Bow.card, in: shape)
    .overlay {
      shape.strokeBorder(accent.opacity(contrast == .increased ? 0.9 : isFilled ? 0.3 : 0.45),
                         lineWidth: contrast == .increased ? 2 : 1.5)
    }
    .contentShape(shape)
    .accessibilityElement(children: .combine)
    .accessibilityValue(assignedShare.map { "\(Int(($0 * 100).rounded())) percent of this month’s money assigned" } ?? "")
  }

  private var amount: some View {
    MoneyText(minor: notice.amountMinor, currencyCode: currencyCode)
      .font(isHero ? .bowTitle : .bowAmount)
      .foregroundStyle(ink)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
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
      .background(isFilled ? accent.opacity(0.18) : tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
      Circle().stroke(Bow.funded.opacity(0.25), lineWidth: 4)
      Circle().trim(from: 0, to: fraction)
        .stroke(Bow.funded, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Image(systemName: symbol)
        .font(.system(size: side * 0.36, weight: .semibold))
        .foregroundStyle(Bow.fundedInk)
    }
    .frame(width: side, height: side)
    .bowAnimation(Bow.ringMotion, value: fraction)
    .accessibilityHidden(true)
  }
}
