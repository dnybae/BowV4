import Foundation
import SwiftData

/// Every transaction as a spreadsheet-friendly CSV, newest first.
struct TransactionCSVExporter {
  func csv(from context: ModelContext) throws -> String {
    let accounts = Dictionary(try context.fetch(FetchDescriptor<BudgetAccount>()).map { ($0.id, $0.name) },
                              uniquingKeysWith: { first, _ in first })
    let envelopes = Dictionary(try context.fetch(FetchDescriptor<BudgetEnvelope>()).map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
    let transactions = try context.fetch(FetchDescriptor<BudgetTransaction>(
      sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
    ))
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyy-MM-dd"
    var lines = ["Date,Account,Payee,Envelope,Amount,Type,Transfer To,Notes,Cleared"]
    for transaction in transactions {
      let amount = (Decimal(transaction.amountMinor) / 100).description
      let fields = [
        dateFormatter.string(from: transaction.date),
        accounts[transaction.accountID] ?? "",
        transaction.payee,
        transaction.envelopeID.flatMap { envelopes[$0] } ?? "",
        amount,
        transaction.isBalanceAdjustment ? "Balance Adjustment" : transaction.kind.title,
        transaction.transferAccountID.flatMap { accounts[$0] } ?? "",
        transaction.notes,
        transaction.isCleared ? "Yes" : "No"
      ]
      lines.append(fields.enumerated().map { index, field in
        // Amount (index 4) is a number; any other field that looks like a formula stays text.
        Self.escaped(index == 4 ? field : Self.neutralized(field))
      }.joined(separator: ","))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Spreadsheets run a cell starting with =, + or @ as a formula; a leading apostrophe keeps it text.
  private static func neutralized(_ field: String) -> String {
    guard let first = field.first, "=+@".contains(first) else { return field }
    return "'" + field
  }

  private static func escaped(_ field: String) -> String {
    guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
