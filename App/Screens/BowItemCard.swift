import SwiftUI

/// A separate rounded card for one destination, such as an envelope or an account:
/// the row's content, then a chevron. Pair it with `.buttonStyle(.bowPress)`.
struct BowItemCard<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      content()
      Image(systemName: "chevron.right")
        .font(.bowFootnote.weight(.semibold))
        .foregroundStyle(Bow.inkFaint)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Bow.Space.s4)
    .frame(maxWidth: .infinity, minHeight: 68)
    .contentShape(.rect(cornerRadius: Bow.itemCardRadius))
    .bowCard(radius: Bow.itemCardRadius)
  }
}
