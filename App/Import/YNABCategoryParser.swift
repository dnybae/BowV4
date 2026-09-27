import Foundation

struct YNABCategoryParser {
  func parse(_ text: String) throws -> YNABCategoryPreview {
    let source = text.replacingOccurrences(of: "\u{FEFF}", with: "")
    let firstLine = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let delimiter: Character = firstLine.filter { $0 == "\t" }.count
      > firstLine.filter { $0 == "," }.count ? "\t" : ","
    let rows = parseRows(source, delimiter: delimiter)
    guard let headers = rows.first else { throw YNABImportError.emptyFile }
    let normalizedHeaders = headers.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    guard let groupColumn = normalizedHeaders.firstIndex(of: "category group"),
          let categoryColumn = normalizedHeaders.firstIndex(of: "category") else {
      throw YNABImportError.missingColumns
    }

    var orderedGroups: [YNABCategoryGroup] = []
    var groupPositions: [String: Int] = [:]
    var seenCategories: Set<String> = []
    for row in rows.dropFirst() {
      guard row.indices.contains(groupColumn), row.indices.contains(categoryColumn)
      else { continue }
      let groupName = cleanName(row[groupColumn])
      let categoryName = cleanName(row[categoryColumn])
      guard !groupName.isEmpty, !categoryName.isEmpty,
            groupName.localizedCaseInsensitiveCompare("Credit Card Payments") != .orderedSame,
            categoryName.localizedCaseInsensitiveCompare("Ready to Assign") != .orderedSame,
            categoryName.localizedCaseInsensitiveCompare("Inflow: Ready to Assign") != .orderedSame
      else { continue }
      let groupKey = groupName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let categoryKey = categoryName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let pairKey = groupKey + "\u{1F}" + categoryKey
      guard seenCategories.insert(pairKey).inserted else { continue }
      if let index = groupPositions[groupKey] {
        orderedGroups[index].envelopes.append(categoryName)
      } else {
        groupPositions[groupKey] = orderedGroups.count
        orderedGroups.append(YNABCategoryGroup(name: groupName, envelopes: [categoryName]))
      }
    }
    guard !orderedGroups.isEmpty else { throw YNABImportError.noCategories }
    return YNABCategoryPreview(groups: orderedGroups)
  }

  private func parseRows(_ source: String, delimiter: Character) -> [[String]] {
    let characters = Array(source)
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\"" {
        if inQuotes && index + 1 < characters.count && characters[index + 1] == "\"" {
          field.append("\"")
          index += 1
        } else {
          inQuotes.toggle()
        }
      } else if character == delimiter && !inQuotes {
        row.append(field)
        field = ""
      } else if (character == "\n" || character == "\r") && !inQuotes {
        if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" {
          index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) {
          rows.append(row)
        }
        row = []
        field = ""
      } else {
        field.append(character)
      }
      index += 1
    }
    row.append(field)
    if row.contains(where: { !$0.isEmpty }) {
      rows.append(row)
    }
    return rows
  }

  private func cleanName(_ value: String) -> String {
    let withoutEmoji = value.filter { character in
      !character.unicodeScalars.contains {
        $0.properties.isEmojiPresentation
          || $0.value == 0xFE0F
          || ($0.properties.isEmoji && $0.value > 0x7F)
      }
    }
    return withoutEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct YNABCategoryPreview {
  var groups: [YNABCategoryGroup]

  var envelopeCount: Int {
    groups.reduce(0) { $0 + $1.envelopes.count }
  }
}

struct YNABCategoryGroup: Identifiable {
  var name: String
  var envelopes: [String]

  var id: String { name }
}

enum YNABImportError: LocalizedError {
  case emptyFile
  case missingColumns
  case noCategories
  case unreadableText

  var errorDescription: String? {
    switch self {
    case .emptyFile: "The file is empty."
    case .missingColumns:
      "Choose a YNAB Plan export with Category Group and Category columns."
    case .noCategories: "No category groups and envelopes were found."
    case .unreadableText: "The file couldn’t be read as text."
    }
  }
}
