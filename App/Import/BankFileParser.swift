import Foundation

enum BankFileFormat: String {
  case csv
  case ofx
  case qfx
  case qif
}

enum BankDateOrder: String, CaseIterable, Identifiable {
  case monthDayYear
  case dayMonthYear
  case yearMonthDay

  var id: String { rawValue }

  var title: String {
    switch self {
    case .monthDayYear: "Month / Day / Year"
    case .dayMonthYear: "Day / Month / Year"
    case .yearMonthDay: "Year / Month / Day"
    }
  }
}

struct BankCSVTable {
  var headers: [String]
  var rows: [[String]]
}

struct BankCSVMapping: Equatable {
  var dateColumn: Int?
  var payeeColumn: Int?
  var memoColumn: Int?
  var amountColumn: Int?
  var outflowColumn: Int?
  var inflowColumn: Int?
  var separateAmounts: Bool = false
  var reverseSigns: Bool = false
  var dateOrder: BankDateOrder = .monthDayYear

  static func suggested(for headers: [String]) -> BankCSVMapping {
    let lower = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func index(_ names: [String]) -> Int? {
      lower.firstIndex(where: { names.contains($0) })
    }
    let outflow = index(["outflow", "debit", "withdrawal", "money out"])
    let inflow = index(["inflow", "credit", "deposit", "money in"])
    return BankCSVMapping(
      dateColumn: index(["date", "posted date", "transaction date", "posting date"]),
      payeeColumn: index(["payee", "description", "merchant", "name"]),
      memoColumn: index(["memo", "notes", "note", "details"]),
      amountColumn: index(["amount", "transaction amount"]),
      outflowColumn: outflow,
      inflowColumn: inflow,
      separateAmounts: outflow != nil && inflow != nil
    )
  }
}

struct BankImportRow {
  var rowNumber: Int
  var date: Date
  var amountMinor: Int64
  var payee: String
  var memo: String
  var externalID: String?
}

enum BankFileParseError: LocalizedError {
  case emptyFile
  case missingColumns
  case invalidRow(Int, String)
  case unsupportedFormat
  case unreadableText

  var errorDescription: String? {
    switch self {
    case .emptyFile: "The file has no transactions."
    case .missingColumns: "Map a date, payee, and amount (or separate outflow and inflow) column."
    case .invalidRow(let row, let detail): "Row \(row): \(detail)"
    case .unsupportedFormat: "Choose a CSV, OFX, QFX, or QIF file."
    case .unreadableText: "The file couldn’t be read as text."
    }
  }
}

struct BankFileParser {
  func csvTable(_ text: String) throws -> BankCSVTable {
    let source = text.replacingOccurrences(of: "\u{FEFF}", with: "")
    let firstLine = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let delimiters: [Character] = [",", "\t", ";"]
    let delimiter = delimiters.max { left, right in
      firstLine.filter { $0 == left }.count < firstLine.filter { $0 == right }.count
    } ?? ","
    let rows = parseDelimitedRows(source, delimiter: delimiter)
    guard let headers = rows.first, !headers.isEmpty else { throw BankFileParseError.emptyFile }
    return BankCSVTable(
      headers: headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
      rows: Array(rows.dropFirst())
    )
  }

  func csvRows(_ table: BankCSVTable, mapping: BankCSVMapping) throws -> [BankImportRow] {
    guard let dateColumn = mapping.dateColumn,
          let payeeColumn = mapping.payeeColumn,
          mapping.separateAmounts
            ? (mapping.outflowColumn != nil && mapping.inflowColumn != nil)
            : mapping.amountColumn != nil else {
      throw BankFileParseError.missingColumns
    }
    var result: [BankImportRow] = []
    for (index, row) in table.rows.enumerated() {
      let rowNumber = index + 2
      func field(_ column: Int?) -> String {
        guard let column, row.indices.contains(column) else { return "" }
        return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let dateText = field(dateColumn)
      guard let date = parseDate(dateText, order: mapping.dateOrder) else {
        throw BankFileParseError.invalidRow(rowNumber, "Invalid date \"\(dateText)\".")
      }
      var amount: Int64
      if mapping.separateAmounts {
        let outflow = field(mapping.outflowColumn)
        let inflow = field(mapping.inflowColumn)
        if outflow.isEmpty && inflow.isEmpty { continue }
        guard outflow.isEmpty || inflow.isEmpty else {
          throw BankFileParseError.invalidRow(rowNumber, "Both outflow and inflow have values.")
        }
        guard let parsed = parseAmount(outflow.isEmpty ? inflow : outflow) else {
          throw BankFileParseError.invalidRow(rowNumber, "Invalid amount.")
        }
        guard let magnitude = Int64(exactly: parsed.magnitude) else {
          throw BankFileParseError.invalidRow(rowNumber, "Amount is too large.")
        }
        amount = outflow.isEmpty ? magnitude : -magnitude
      } else {
        guard let parsed = parseAmount(field(mapping.amountColumn)) else {
          throw BankFileParseError.invalidRow(rowNumber, "Invalid amount.")
        }
        amount = parsed
      }
      if mapping.reverseSigns {
        guard amount != Int64.min else {
          throw BankFileParseError.invalidRow(rowNumber, "Amount is too large to reverse.")
        }
        amount = -amount
      }
      guard amount != 0 else { continue }
      result.append(BankImportRow(
        rowNumber: rowNumber,
        date: date,
        amountMinor: amount,
        payee: field(payeeColumn),
        memo: field(mapping.memoColumn),
        externalID: nil
      ))
    }
    guard !result.isEmpty else { throw BankFileParseError.emptyFile }
    return result
  }

  func ofxRows(_ text: String) throws -> [BankImportRow] {
    let blocks = matches("(?is)<STMTTRN>(.*?)(?:</STMTTRN>|(?=<STMTTRN>)|(?=</BANKTRANLIST>))", in: text)
    var result: [BankImportRow] = []
    for (index, block) in blocks.enumerated() {
      let rowNumber = index + 1
      let dateText = tag("DTPOSTED", in: block) ?? ""
      let amountText = tag("TRNAMT", in: block) ?? ""
      guard let date = parseOFXDate(dateText), let amount = parseAmount(amountText) else {
        throw BankFileParseError.invalidRow(rowNumber, "Missing or invalid OFX date or amount.")
      }
      guard amount != 0 else { continue }
      result.append(BankImportRow(
        rowNumber: rowNumber,
        date: date,
        amountMinor: amount,
        payee: unescape(tag("NAME", in: block) ?? tag("PAYEE", in: block) ?? tag("MEMO", in: block) ?? "Transaction"),
        memo: unescape(tag("MEMO", in: block) ?? ""),
        externalID: tag("FITID", in: block)
      ))
    }
    guard !result.isEmpty else { throw BankFileParseError.emptyFile }
    return result
  }

  func qifRows(_ text: String, dateOrder: BankDateOrder) throws -> [BankImportRow] {
    var result: [BankImportRow] = []
    var fields: [Character: String] = [:]
    func appendRecord() throws {
      guard !fields.isEmpty else { return }
      let rowNumber = result.count + 1
      let dateText = fields["D"] ?? ""
      let amountText = fields["T"] ?? fields["U"] ?? ""
      guard let date = parseDate(dateText.replacingOccurrences(of: "'", with: "/"), order: dateOrder),
            let amount = parseAmount(amountText) else {
        throw BankFileParseError.invalidRow(rowNumber, "Missing or invalid QIF date or amount.")
      }
      guard amount != 0 else { return }
      result.append(BankImportRow(
        rowNumber: rowNumber,
        date: date,
        amountMinor: amount,
        payee: fields["P"] ?? "Transaction",
        memo: fields["M"] ?? "",
        externalID: nil
      ))
    }
    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line == "^" {
        try appendRecord()
        fields = [:]
      } else if !line.isEmpty && !line.hasPrefix("!") {
        let key = line.first!
        if ["D", "T", "U", "P", "M"].contains(key) {
          fields[key] = String(line.dropFirst())
        }
      }
    }
    try appendRecord()
    guard !result.isEmpty else { throw BankFileParseError.emptyFile }
    return result
  }

  private func parseDelimitedRows(_ source: String, delimiter: Character) -> [[String]] {
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
        if row.contains(where: { !$0.allSatisfy(\.isWhitespace) }) { rows.append(row) }
        row = []
        field = ""
      } else {
        field.append(character)
      }
      index += 1
    }
    row.append(field)
    if row.contains(where: { !$0.allSatisfy(\.isWhitespace) }) { rows.append(row) }
    return rows
  }

  private func parseDate(_ value: String, order: BankDateOrder) -> Date? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formats: [String]
    switch order {
    case .monthDayYear: formats = ["M/d/yyyy", "M/d/yy", "yyyy-MM-dd", "yyyy/MM/dd"]
    case .dayMonthYear: formats = ["d/M/yyyy", "d/M/yy", "yyyy-MM-dd", "yyyy/MM/dd"]
    case .yearMonthDay: formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyyMMdd"]
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.isLenient = false
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }

  private func parseOFXDate(_ value: String) -> Date? {
    guard value.count >= 8 else { return nil }
    return parseDate(String(value.prefix(8)), order: .yearMonthDay)
  }

  private func parseAmount(_ value: String) -> Int64? {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "$", with: "")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\u{2212}", with: "-")
    if text.hasPrefix("(") && text.hasSuffix(")") {
      text = "-" + String(text.dropFirst().dropLast())
    }
    if text.contains(",") && !text.contains(".") {
      let decimalDigits = text.split(separator: ",").last?.count ?? 0
      text = decimalDigits == 2
        ? text.replacingOccurrences(of: ",", with: ".")
        : text.replacingOccurrences(of: ",", with: "")
    } else {
      text = text.replacingOccurrences(of: ",", with: "")
    }
    guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
      return nil
    }
    let minor = decimal * 100
    var rounded = Decimal()
    var input = minor
    NSDecimalRound(&rounded, &input, 0, .plain)
    guard minor == rounded, minor <= Decimal(Int64.max), minor >= Decimal(Int64.min) else {
      return nil
    }
    return Int64(NSDecimalNumber(decimal: minor).stringValue)
  }

  private func matches(_ pattern: String, in source: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
      guard match.numberOfRanges > 1,
            let body = Range(match.range(at: 1), in: source) else { return nil }
      return String(source[body])
    }
  }

  private func tag(_ name: String, in source: String) -> String? {
    matches("(?i)<\(name)>\\s*([^<\\r\\n]*)", in: source)
      .first?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func unescape(_ value: String) -> String {
    value.replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
  }
}
