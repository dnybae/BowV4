import SwiftUI

/// The top of a name-first editor (envelope, account, payee): the icon tile over a centered
/// SF Rounded name field. Takes the place of the amount hero. Place it in a List row with a clear background.
struct BowNameHeader<Tile: View>: View {
  var placeholder: String
  @Binding var name: String
  /// Lets an editor put the cursor in the name, e.g. when creating something new.
  var isFocused: FocusState<Bool>.Binding?
  @ViewBuilder var tile: () -> Tile

  init(placeholder: String, name: Binding<String>, isFocused: FocusState<Bool>.Binding? = nil,
       @ViewBuilder tile: @escaping () -> Tile) {
    self.placeholder = placeholder
    _name = name
    self.isFocused = isFocused
    self.tile = tile
  }

  var body: some View {
    VStack(spacing: Bow.Space.s3) {
      tile()
      if let isFocused {
        field.focused(isFocused)
      } else {
        field
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s2)
  }

  private var field: some View {
    TextField(placeholder, text: $name)
      .font(.bowTitle)
      .foregroundStyle(Bow.ink)
      .multilineTextAlignment(.center)
      .submitLabel(.done)
      .accessibilityLabel("Name")
  }
}

extension BowNameHeader where Tile == BowGlossyTile {
  init(_ placeholder: String, name: Binding<String>, systemImage: String) {
    self.init(placeholder: placeholder, name: name) {
      BowGlossyTile(systemImage: systemImage)
    }
  }
}
