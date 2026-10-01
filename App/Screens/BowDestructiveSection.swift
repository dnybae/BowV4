import SwiftUI

/// A red text row in its own section at the bottom of an editor, e.g. "Delete transaction".
/// Only include it when the action applies.
struct BowDestructiveSection: View {
  var title: String
  var action: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Section {
      Button(title, role: .destructive, action: action)
        .foregroundStyle(Bow.overInk)
        .listRowBackground(Bow.card)
    }
  }
}
