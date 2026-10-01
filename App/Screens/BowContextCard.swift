import SwiftUI

/// A glass card at the top of the approve and target sheets: a 44pt tile, the name,
/// one context line and a trailing pill or picker.
struct BowContextCard<Tile: View, Trailing: View>: View {
  var name: String
  var context: String? = nil
  @ViewBuilder var tile: () -> Tile
  @ViewBuilder var trailing: () -> Trailing
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s3))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s3))
    layout {
      HStack(spacing: Bow.Space.s3) {
        tile()
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
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .padding(Bow.Space.s4)
    .bowGlassCard()
  }
}

extension BowContextCard where Tile == BowGlossyTile {
  init(name: String, systemImage: String, context: String? = nil,
       @ViewBuilder trailing: @escaping () -> Trailing) {
    self.init(name: name, context: context, tile: { BowGlossyTile(systemImage: systemImage, size: 44) },
              trailing: trailing)
  }
}

extension BowContextCard where Trailing == EmptyView {
  init(name: String, context: String? = nil, @ViewBuilder tile: @escaping () -> Tile) {
    self.init(name: name, context: context, tile: tile, trailing: { EmptyView() })
  }
}
