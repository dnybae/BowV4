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

  /// Review and scheduled rows sit on a tinted background, so their logo uses the white tile.
  private var isHighlighted: Bool {
    switch model.state {
    case .attention, .scheduled: true
    case .normal, .pending: false
    }
  }

  private var amountText: String {
    BudgetMoney.formatted(model.amountMinor, currencyCode: currencyCode, showsPlusSign: model.isInflow)
  }

  /// State and subtitle, spoken after the amount.
  private var accessibilityDetail: String {
    let subtitle = model.subtitle(hiding: options)
    switch model.state {
    case .normal:
      let note = model.isPendingAtBank ? "Pending at bank" : model.isScheduledEntry ? "Entered from schedule" : nil
      return [subtitle, note].compactMap { $0 }.joined(separator: ", ")
    case .pending(let label), .attention(let label, _), .scheduled(let label):
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
            .foregroundStyle(Bow.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          secondaryLine
        }
        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: Bow.Space.s2)
        }
        HStack(spacing: Bow.Space.s1) {
          MoneyText(minor: model.amountMinor, currencyCode: currencyCode, showsPlusSign: model.isInflow)
            .font(.bowAmount)
            .foregroundStyle(model.isInflow ? Bow.fundedInk : Bow.ink)
          if model.isMatched {
            Image(systemName: "link")
              .font(.bowFootnote.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
              .accessibilityHidden(true)
          }
          if let symbol = model.amountSymbol {
            Image(systemName: symbol)
              .font(.bowFootnote.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
              .accessibilityHidden(true)
          }
        }
      }
    }
    // Not in the budget yet: the whole row is greyed out, like YNAB.
    .opacity(isPending ? 0.45 : 1)
    .padding(.vertical, Bow.Space.s1)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.title)
    .accessibilityValue([amountText, accessibilityDetail, model.isMatched ? "Matched with bank transaction" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
  }

  private var logo: some View {
    MerchantLogoView(
      merchantName: model.logoName,
      domain: model.merchantDomain,
      kind: model.kind,
      envelopeName: model.envelopeName,
      size: 40,
      style: isHighlighted ? .glossy : .plain
    )
  }

  /// One line only: a status line replaces the subtitle rather than adding a line.
  @ViewBuilder
  private var secondaryLine: some View {
    if let status = model.state.rowStatus {
      TransactionStatusLine(status: status, text: model.state.label)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    } else if let subtitle = model.subtitle(hiding: options) {
      Text(subtitle)
        .font(.bowSubhead)
        .foregroundStyle(Bow.inkSoft)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
  }
}
