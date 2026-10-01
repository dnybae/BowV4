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
      .bowScaledIcon(frame: 30, glyph: 15, weight: .medium)
      .foregroundStyle(Bow.bowInk)
      .background(Bow.bowTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityHidden(true)
  }
}

extension BowTileIcon where Icon == Image {
  init(systemImage: String) {
    self.icon = { Image(systemName: systemImage) }
  }
}

/// A form row's title: plain text, or an icon-tile label when a symbol is given.
struct BowFieldTitle: View {
  var title: String
  var systemImage: String?

  var body: some View {
    if let systemImage {
      Label(title, systemImage: systemImage)
        .labelStyle(.bowTile)
        .foregroundStyle(Bow.ink)
    } else {
      Text(title).foregroundStyle(Bow.ink)
    }
  }
}
