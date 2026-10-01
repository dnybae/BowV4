import SwiftUI

/// The centered block that opens every detail screen: tile, name, one context line,
/// the hero amount and an optional status pill. Place it in a List row with a clear background.
struct BowIdentityHeader<Tile: View>: View {
  var name: String
  var context: String? = nil
  var amountMinor: Int64? = nil
  var currencyCode: String = "USD"
  var amountColor: Color = Bow.ink
  var pill: StatusPill? = nil
  @ViewBuilder var tile: () -> Tile

  var body: some View {
    VStack(spacing: Bow.Space.s2) {
      tile()
        .padding(.bottom, Bow.Space.s2)
      VStack(spacing: Bow.Space.s1) {
        Text(name)
          .font(.bowTitle)
          .foregroundStyle(Bow.ink)
        if let context {
          Text(context)
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
        }
      }
      .accessibilityElement(children: .combine)
      if let amountMinor {
        MoneyText(minor: amountMinor, currencyCode: currencyCode)
          .bowHeroFont()
          .foregroundStyle(amountColor)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      if let pill {
        pill.padding(.top, Bow.Space.s1)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s2)
  }
}

extension BowIdentityHeader where Tile == BowGlossyTile {
  /// An identity block whose tile is an SF Symbol, e.g. an account, envelope or SimpleFIN.
  init(name: String, systemImage: String, context: String? = nil, amountMinor: Int64? = nil,
       currencyCode: String = "USD", amountColor: Color = Bow.ink, pill: StatusPill? = nil) {
    self.init(name: name, context: context, amountMinor: amountMinor, currencyCode: currencyCode,
              amountColor: amountColor, pill: pill) {
      BowGlossyTile(systemImage: systemImage)
    }
  }
}
