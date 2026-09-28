import SwiftUI

struct SettingsPlaceholderScreen: View {
  var title: String
  var description: String
  var systemImage: String

  var body: some View {
    ContentUnavailableView(
      title, systemImage: systemImage,
      description: Text(description)
    )
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
