import SwiftUI

/// Shown instead of crashing when the saved budget can't be opened. Nothing is deleted.
struct StoreUnavailableScreen: View {
  var message: String
  var onRetry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Couldn’t open your budget", systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      Text("Your budget is still saved on this iPhone. Try again, or contact us and we’ll help you get it back.\n\n\(message)")
    } actions: {
      Button("Try Again", action: onRetry)
        .bowPrimaryButton(size: .regular)
        .fixedSize()
      Link("Email Support", destination: SupportLink.email(subject: "Bow couldn’t open my budget"))
        .bowSecondaryButton(size: .regular)
        .fixedSize()
    }
    .background { Bow.mist.ignoresSafeArea() }
    .bowAppTint()
  }
}
