import Foundation

struct BankTransactionMatcher {
  func decide(
    for incoming: BankTransactionCandidate,
    among existing: [LocalTransactionCandidate]
  ) -> BankMatchDecision {
    if let linked = existing.first(where: { $0.externalKey == incoming.externalKey }) {
      return .alreadyImported(linked.id)
    }

    let manual = existing.filter {
      $0.accountID == incoming.accountID && $0.externalKey == nil && $0.isManual
    }
    let near = manual.filter {
      abs($0.date.timeIntervalSince(incoming.transactedAt ?? incoming.postedAt))
        <= 5 * 24 * 60 * 60
    }
    let sameAmount = near.filter { $0.amountMinor == incoming.amountMinor }
    let exact = sameAmount.filter {
      normalized($0.payee) == normalized(incoming.description)
        && !normalized($0.payee).isEmpty
    }
    if exact.count == 1 {
      return .linkManual(exact[0].id)
    }
    if exact.count > 1 {
      return .review(exact.map(\.id))
    }

    let similar = near.filter {
      $0.amountMinor == incoming.amountMinor
        || normalized($0.payee) == normalized(incoming.description)
    }
    if !similar.isEmpty {
      return .review(similar.map(\.id))
    }
    return .createNew
  }

  private func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: .punctuationCharacters)
      .joined(separator: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}

struct BankTransactionCandidate: Sendable {
  var externalKey: String
  var accountID: UUID
  var amountMinor: Int64
  var postedAt: Date
  var transactedAt: Date?
  var description: String
}

struct LocalTransactionCandidate: Sendable {
  var id: UUID
  var accountID: UUID
  var amountMinor: Int64
  var date: Date
  var payee: String
  var externalKey: String?
  var isManual: Bool
}

enum BankMatchDecision: Equatable, Sendable {
  case alreadyImported(UUID)
  case linkManual(UUID)
  case review([UUID])
  case createNew
}
