import Foundation

struct BankImportProposal: Identifiable, Sendable {
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
    let calendar = Calendar.current
    var byDay: [Date: [LocalTransactionCandidate]] = [:]
    var byExternalKey: [String: LocalTransactionCandidate] = [:]
    for candidate in existing {
      byDay[calendar.startOfDay(for: candidate.date), default: []].append(candidate)
      if let key = candidate.externalKey, byExternalKey[key] == nil {
        byExternalKey[key] = candidate
      }
    }
    var transfersByDay: [Date: [LocalTransactionCandidate]] = [:]
    for candidate in manualTransfers {
      transfersByDay[calendar.startOfDay(for: candidate.date), default: []].append(candidate)
    }
    func nearby(_ date: Date, in index: [Date: [LocalTransactionCandidate]]) -> [LocalTransactionCandidate] {
      let day = calendar.startOfDay(for: date)
      return (-6...6).flatMap { offset in
        guard let key = calendar.date(byAdding: .day, value: offset, to: day) else { return [LocalTransactionCandidate]() }
        return index[key] ?? []
      }
    }
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

      let candidates = nearby(row.date, in: byDay)
      let transferMatches = nearby(row.date, in: transfersByDay).filter {
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
      if let linked = byExternalKey[externalKey] {
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
        if let linked = candidates.first(where: { $0.id == id }) {
          let day = calendar.startOfDay(for: linked.date)
          if var bucket = byDay[day], let index = bucket.firstIndex(where: { $0.id == id }) {
            bucket[index].externalKey = externalKey
            bucket[index].isManual = false
            byExternalKey[externalKey] = bucket[index]
            byDay[day] = bucket
          }
        }
      case .createNew:
        let created = LocalTransactionCandidate(
          id: UUID(),
          accountID: accountID,
          amountMinor: row.amountMinor,
          date: row.date,
          payee: row.payee,
          externalKey: externalKey,
          isManual: false
        )
        byDay[calendar.startOfDay(for: row.date), default: []].append(created)
        byExternalKey[externalKey] = created
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
