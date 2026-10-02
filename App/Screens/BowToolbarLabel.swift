import SwiftUI

/// The label for every toolbar button, so text and symbols share one medium weight.
/// Toolbars ignore weight modifiers on the button, and on symbols even inside the label,
/// so text gets its font here and symbols get the weight baked into the image.
struct BowToolbarLabel: View {
  var title: String
  var systemImage: String?

  init(_ title: String, systemImage: String? = nil) {
    self.title = title
    self.systemImage = systemImage
  }

  var body: some View {
    if let systemImage {
      Label {
        Text(title)
      } icon: {
        Image(uiImage: Self.symbol(systemImage))
      }
    } else {
      Text(title).font(.bowToolbar)
    }
  }

  private static func symbol(_ name: String) -> UIImage {
    let configuration = UIImage.SymbolConfiguration(weight: .medium)
    let image = UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()
    return image.withRenderingMode(.alwaysTemplate)
  }
}
