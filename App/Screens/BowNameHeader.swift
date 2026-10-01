import SwiftUI

/// The top of a name-first editor (envelope, account, payee): the icon tile over a centered
/// SF Rounded name field. Takes the place of the amount hero. Place it in a List row with a clear background.
struct BowNameHeader<Tile: View>: View {
  var placeholder: String
  @Binding var name: String
  @ViewBuilder var tile: () -> Tile

  var body: some View {
    VStack(spacing: Bow.Space.s3) {
      tile()
      TextField(placeholder, text: $name)
        .font(.bowTitle)
        .foregroundStyle(Bow.ink)
        .multilineTextAlignment(.center)
        .submitLabel(.done)
        .accessibilityLabel("Name")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s2)
  }
}

extension BowNameHeader where Tile == BowGlossyTile {
  init(_ placeholder: String, name: Binding<String>, systemImage: String) {
    self.init(placeholder: placeholder, name: name) {
      BowGlossyTile(systemImage: systemImage)
    }
  }
}
