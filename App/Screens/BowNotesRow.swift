import SwiftUI

/// A note tile, "Notes" and an "Add a note" field. A note is a short memo you type yourself:
/// it grows to fit instead of scrolling, and Return finishes editing.
struct BowNotesRow: View {
  @Binding var notes: String
  @FocusState private var isFocused: Bool

  private var showsCount: Bool { notes.count >= NoteText.counterThreshold }

  var body: some View {
    // A plain HStack, so the list row grows with the text instead of clipping it.
    HStack(spacing: Bow.Space.s3) {
      Label("Notes", systemImage: "note.text")
        .labelStyle(.bowTile)
        .foregroundStyle(Bow.ink)
        .accessibilityHidden(true)
      Spacer(minLength: Bow.Space.s2)
      VStack(alignment: .trailing, spacing: 2) {
        TextField("Add a note", text: $notes, axis: .vertical)
          .multilineTextAlignment(.trailing)
          .focused($isFocused)
          .submitLabel(.done)
          .accessibilityLabel("Notes")
          .accessibilityHint("Up to \(NoteText.maxLength) characters")
        if showsCount {
          Text("\(notes.count)/\(NoteText.maxLength)")
            .font(.bowFootnote)
            .monospacedDigit()
            .foregroundStyle(notes.count >= NoteText.maxLength ? Bow.needsInk : Bow.inkSoft)
            .accessibilityLabel("\(NoteText.maxLength - notes.count) characters left")
        }
      }
    }
    .onChange(of: notes) { _, newValue in
      // Return arrives as a line break in a growing field: finish editing instead.
      if newValue.contains(where: \.isNewline) { isFocused = false }
      let limited = NoteText.limited(newValue)
      if limited != newValue { notes = limited }
    }
  }
}
