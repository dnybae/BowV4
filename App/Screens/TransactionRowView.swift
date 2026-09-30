import SwiftUI

/// The one transaction row used everywhere: logo, title, one secondary line, amount.
/// Display only; the containing screen owns taps, navigation and swipe actions.
struct TransactionRowView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var model: TransactionRowModel
  var currencyCode: String
  var options: TransactionRowOptions = []

  private var isPending: Bool {
    if case .pending = model.state { return true }
    return false
  }

  private var needsAttention: Bool {
    if case .attention = model.state { return true }
    return false
  }

  private var amountText: String {
    BudgetMoney.formatted(model.amountMinor, currencyCode: currencyCode, showsPlusSign: model.isInflow)
  }

  /// State and subtitle, spoken after the amount.
  private var accessibilityDetail: String {
    let subtitle = model.subtitle(hiding: options)
    switch model.state {
    case .normal: return subtitle ?? ""
    case .pending(let label), .attention(let label, _):
      return [subtitle, label].compactMap { $0 }.joined(separator: ", ")
    }
  }

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      logo
      let layout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s1))
        : AnyLayout(HStackLayout(spacing: Bow.Space.s2))
      layout {
        VStack(alignment: .leading, spacing: 2) {
          Text(model.title)
            .font(.bowHeadline)
            .foregroundStyle(isPending ? Bow.inkSoft : Bow.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          secondaryLine
        }
        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: Bow.Space.s2)
        }
        MoneyText(minor: model.amountMinor, currencyCode: currencyCode, showsPlusSign: model.isInflow)
          .font(.bowAmount)
          .foregroundStyle(isPending ? Bow.inkSoft : model.isInflow ? Bow.fundedInk : Bow.ink)
      }
    }
    .padding(.vertical, Bow.Space.s1)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.title)
    .accessibilityValue([amountText, accessibilityDetail].filter { !$0.isEmpty }.joined(separator: ", "))
  }

  private var logo: some View {
    MerchantLogoView(
      merchantName: model.logoName,
      domain: model.merchantDomain,
      kind: model.kind,
      categoryName: model.envelopeName,
      size: 40
    )
    .opacity(isPending ? 0.6 : 1)
    .overlay(alignment: .bottomTrailing) {
      if needsAttention {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(Bow.needs)
          .background(Circle().fill(Bow.card).padding(-2))
          .offset(x: 4, y: 4)
      }
    }
  }

  /// One line only: an attention or pending state replaces the subtitle rather than adding a line.
  @ViewBuilder
  private var secondaryLine: some View {
    switch model.state {
    case .normal:
      if let subtitle = model.subtitle(hiding: options) {
        Text(subtitle)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      }
    case .pending(let label):
      Label(label, systemImage: "clock")
        .font(.bowSubhead)
        .foregroundStyle(Bow.inkSoft)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    case .attention(let label, let symbol):
      Label(label, systemImage: symbol)
        .font(.bowSubhead.weight(.medium))
        .foregroundStyle(Bow.needsInk)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
  }
}
