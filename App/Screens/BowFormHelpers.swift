import SwiftUI

extension View {
  /// Editor sheets: the keyboard follows a downward drag, and a swipe down can't silently
  /// throw away changes. While there are changes, Cancel asks first (see `BowCancelButton`).
  func bowEditorSheet(hasChanges: Bool) -> some View {
    self
      .scrollDismissesKeyboard(.interactively)
      .interactiveDismissDisabled(hasChanges)
  }

  /// An error alert driven by an optional message: it shows while the message is set.
  func bowErrorAlert(_ title: String, message: Binding<String?>) -> some View {
    alert(title, isPresented: Binding(
      get: { message.wrappedValue != nil },
      set: { if !$0 { message.wrappedValue = nil } }
    )) {
      Button("OK") { message.wrappedValue = nil }
    } message: {
      Text(message.wrappedValue ?? "")
    }
  }
}

/// Cancel for an editor sheet. With unsaved changes it asks before discarding them.
struct BowCancelButton: ToolbarContent {
  var hasChanges: Bool
  var discardTitle = "Discard Changes"
  var onCancel: () -> Void
  @State private var confirming = false

  var body: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Cancel") {
        if hasChanges { confirming = true } else { onCancel() }
      }
      .confirmationDialog("Discard your changes?", isPresented: $confirming) {
        Button(discardTitle, role: .destructive, action: onCancel)
        Button("Keep Editing", role: .cancel) {}
      }
    }
  }
}

/// The primary action of a money sheet, riding above the keyboard at the bottom of the screen.
/// One per sheet; sheets that use it have no Save button in the toolbar.
struct BowBottomAction<Label: View>: View {
  var isEnabled: Bool
  var action: () -> Void
  @ViewBuilder var label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .fontWeight(.semibold)
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .bowPrimaryButton()
    .disabled(!isEnabled)
    .padding(.horizontal, Bow.Space.s4)
    .padding(.bottom, Bow.Space.s2)
  }
}

extension BowBottomAction where Label == Text {
  init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
    self.init(isEnabled: isEnabled, action: action) { Text(title) }
  }
}
