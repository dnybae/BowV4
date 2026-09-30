import SwiftUI

struct ComingSoonRowLabel: View {
  var title: String
  var systemImage: String

  var body: some View {
    HStack {
      Label(title, systemImage: systemImage)
        .labelStyle(.bowTile)
      Spacer(minLength: 8)
      Text("Soon")
        .font(.subheadline)
        .foregroundStyle(Bow.inkSoft)
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint("Coming soon")
  }
}
