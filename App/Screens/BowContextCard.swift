import SwiftUI

/// A glass card at the top of the approve and target sheets: a 44pt tile, the name,
/// one context line and a trailing pill or picker.
struct BowContextCard<Tile: View, Title: View, Trailing: View>: View {
  @ViewBuilder var tile: () -> Tile
  /// The name and context line. Usually `BowContextTitle`; an editor can put a name field here.
  @ViewBuilder var title: () -> Title
  @ViewBuilder var trailing: () -> Trailing
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s3))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s3))
    layout {
      HStack(spacing: Bow.Space.s3) {
        tile()
        title()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .padding(Bow.Space.s4)
    .bowGlassCard()
  }
}

/// The context card's usual title: the name over one secondary line.
struct BowContextTitle: View {
  var name: String
  var context: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(name)
        .font(.bowHeadline)
        .foregroundStyle(Bow.ink)
      if let context {
        Text(context)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

extension BowContextCard where Title == BowContextTitle {
  init(name: String, context: String? = nil,
       @ViewBuilder tile: @escaping () -> Tile, @ViewBuilder trailing: @escaping () -> Trailing) {
    self.init(tile: tile, title: { BowContextTitle(name: name, context: context) }, trailing: trailing)
  }
}

extension BowContextCard where Tile == BowGlossyTile, Title == BowContextTitle {
  init(name: String, systemImage: String, context: String? = nil,
       @ViewBuilder trailing: @escaping () -> Trailing) {
    self.init(name: name, context: context, tile: { BowGlossyTile(systemImage: systemImage, size: 44) },
              trailing: trailing)
  }
}

extension BowContextCard where Title == BowContextTitle, Trailing == EmptyView {
  init(name: String, context: String? = nil, @ViewBuilder tile: @escaping () -> Tile) {
    self.init(name: name, context: context, tile: tile, trailing: { EmptyView() })
  }
}
