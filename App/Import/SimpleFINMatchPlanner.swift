import Foundation

struct SimpleFINMatchPlanner {
  func decide(
    for incoming: BankTransactionCandidate,
    among existing: [LocalTransactionCandidate]
  ) -> BankMatchDecision {
    if let linked = existing.first(where: { $0.externalKey == incoming.externalKey }) {
      return .alreadyImported(linked.id)
    }
    let date = incoming.transactedAt ?? incoming.postedAt
    let nearby = existing.filter {
      $0.accountID == incoming.accountID && $0.isManual && $0.externalKey == nil
        && abs($0.date.timeIntervalSince(date)) <= 10 * 86_400
    }
    let sameAmount = nearby.filter { $0.amountMinor == incoming.amountMinor }
    if sameAmount.count == 1 { return .linkManual(sameAmount[0].id) }
    if sameAmount.count > 1 { return .review(sameAmount.map(\.id)) }
    let similarPayee = nearby.filter {
      !normalized($0.payee).isEmpty
        && normalized($0.payee) == normalized(incoming.description)
    }
    if !similarPayee.isEmpty { return .review(similarPayee.map(\.id)) }
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
