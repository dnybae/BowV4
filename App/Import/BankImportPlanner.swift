import Foundation

struct BankImportProposal: Identifiable {
  var externalKey: String
  var row: BankImportRow
  var decision: BankMatchDecision

  var id: String { externalKey }
}

struct BankImportPlanner {
  func plan(
    rows: [BankImportRow],
    accountID: UUID,
    existing: [LocalTransactionCandidate],
    manualTransfers: [LocalTransactionCandidate] = []
  ) -> [BankImportProposal] {
    let matcher = BankTransactionMatcher()
    var candidates = existing
    var seenKeys: Set<String> = []
    var fingerprintCounts: [String: Int] = [:]
    var result: [BankImportProposal] = []
    for row in rows {
      let externalKey: String
      if let id = row.externalID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
        externalKey = "bank|\(accountID.uuidString)|\(id)"
      } else {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: row.date)
        let source = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(row.amountMinor)|\(row.payee.lowercased())|\(row.memo.lowercased())"
        let fingerprint = Data(source.utf8).base64EncodedString()
        let ordinal = fingerprintCounts[fingerprint, default: 0]
        fingerprintCounts[fingerprint] = ordinal + 1
        externalKey = "file|\(accountID.uuidString)|\(fingerprint)|\(ordinal)"
      }
      guard seenKeys.insert(externalKey).inserted else { continue }

      let transferMatches = manualTransfers.filter {
        $0.accountID == accountID && $0.amountMinor == row.amountMinor
          && abs($0.date.timeIntervalSince(row.date)) <= 5 * 24 * 60 * 60
      }
      let otherFileMatches = candidates.filter {
        $0.accountID == accountID && $0.externalKey != nil
          && $0.externalKey != externalKey && $0.amountMinor == row.amountMinor
          && abs($0.date.timeIntervalSince(row.date)) <= 2 * 24 * 60 * 60
          && normalized($0.payee) == normalized(row.payee)
      }
      let decision: BankMatchDecision
      if let linked = candidates.first(where: { $0.externalKey == externalKey }) {
        decision = .alreadyImported(linked.id)
      } else if !transferMatches.isEmpty {
        decision = .review(transferMatches.map(\.id))
      } else if !otherFileMatches.isEmpty {
        decision = .review(otherFileMatches.map(\.id))
      } else {
        decision = matcher.decide(
          for: BankTransactionCandidate(
            externalKey: externalKey,
            accountID: accountID,
            amountMinor: row.amountMinor,
            postedAt: row.date,
            transactedAt: nil,
            description: row.payee
          ),
          among: candidates
        )
      }
      result.append(BankImportProposal(externalKey: externalKey, row: row, decision: decision))

      switch decision {
      case .linkManual(let id):
        if let index = candidates.firstIndex(where: { $0.id == id }) {
          candidates[index].externalKey = externalKey
          candidates[index].isManual = false
        }
      case .createNew:
        candidates.append(LocalTransactionCandidate(
          id: UUID(),
          accountID: accountID,
          amountMinor: row.amountMinor,
          date: row.date,
          payee: row.payee,
          externalKey: externalKey,
          isManual: false
        ))
      case .alreadyImported, .review:
        break
      }
    }
    return result
  }

  private func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: .punctuationCharacters)
      .joined(separator: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}
