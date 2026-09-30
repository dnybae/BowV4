import SwiftUI

struct SettingsPlaceholderScreen: View {
  var title: String
  var description: String
  var systemImage: String
  var isComingSoon: Bool = false

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    } actions: {
      if isComingSoon {
        Text("Coming soon")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.tint.opacity(0.12), in: .capsule)
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
