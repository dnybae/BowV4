import Foundation

/// Notes are a quick memo: one paragraph, short enough to read in full without scrolling.
enum NoteText {
  static let maxLength = 80
  /// The character count shows once a note gets this long.
  static let counterThreshold = 60

  /// Keeps a note within the limit. A Return typed at the end is dropped, since it ends editing;
  /// line breaks inside pasted text become spaces.
  static func limited(_ text: String) -> String {
    var trimmed = text
    while trimmed.last?.isNewline == true { trimmed.removeLast() }
    let singleLine = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .joined(separator: " ")
    return String(singleLine.prefix(maxLength))
  }
}
