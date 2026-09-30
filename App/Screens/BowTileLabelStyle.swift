import SwiftUI

/// Settings-style label: the SF Symbol sits in a small tinted tile beside the title.
struct BowTileLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: Bow.Space.s3) {
      BowTileIcon { configuration.icon }
      configuration.title
    }
  }
}

extension LabelStyle where Self == BowTileLabelStyle {
  static var bowTile: BowTileLabelStyle { BowTileLabelStyle() }
}

/// The tinted tile that holds a settings row's symbol.
struct BowTileIcon<Icon: View>: View {
  @ViewBuilder var icon: () -> Icon

  var body: some View {
    icon()
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(Bow.bowInk)
      .frame(width: 30, height: 30)
      .background(Bow.bowTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityHidden(true)
  }
}

extension BowTileIcon where Icon == Image {
  init(systemImage: String) {
    self.icon = { Image(systemName: systemImage) }
  }
}
