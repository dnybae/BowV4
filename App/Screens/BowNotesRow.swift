import SwiftUI

/// The last row of an editor's main section: a note tile, "Notes" and an "Add a note" field.
struct BowNotesRow: View {
  @Binding var notes: String

  var body: some View {
    LabeledContent {
      TextField("Add a note", text: $notes, axis: .vertical)
        .multilineTextAlignment(.trailing)
        .lineLimit(1...4)
        .accessibilityLabel("Notes")
    } label: {
      Label("Notes", systemImage: "note.text")
        .labelStyle(.bowTile)
    }
  }
}
