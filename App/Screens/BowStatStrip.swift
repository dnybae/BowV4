import SwiftUI

/// One glass capsule with up to three centered stats: label above, SF Rounded value below.
/// At accessibility text sizes the stats stack as label–value rows.
struct BowStatStrip: View {
  var stats: [BowStat]
  var currencyCode: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s2))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s2))
    layout {
      ForEach(stats) { stat in
        statView(stat)
      }
    }
    .padding(.vertical, Bow.Space.s3)
    .padding(.horizontal, Bow.Space.s2)
    .bowGlassCard()
  }

  private func statView(_ stat: BowStat) -> some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(VStackLayout(spacing: 2))
    return layout {
      Text(stat.title)
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
      Group {
        switch stat.value {
        case .money(let minor):
          MoneyText(minor: minor, currencyCode: currencyCode)
        case .text(let text):
          Text(text).fontDesign(.rounded)
        }
      }
      .font(.bowAmount)
      .foregroundStyle(stat.color)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Bow.Space.s2 : 0)
    .accessibilityElement(children: .combine)
  }
}

struct BowStat: Identifiable {
  var title: String
  var value: Value
  var color: Color = Bow.ink

  var id: String { title }

  enum Value {
    case money(Int64)
    /// A non-money value, e.g. a reconciled date.
    case text(String)
  }

  static func money(_ title: String, _ minor: Int64, color: Color = Bow.ink) -> BowStat {
    BowStat(title: title, value: .money(minor), color: color)
  }

  static func text(_ title: String, _ text: String, color: Color = Bow.ink) -> BowStat {
    BowStat(title: title, value: .text(text), color: color)
  }
}
