import Foundation

struct PayeeRuleMatcher {
  func envelopeID(for payee: String, rules: [PayeeRuleItem]) -> UUID? {
    let key = normalized(payee)
    guard !key.isEmpty else { return nil }
    let matches = rules.filter { normalized($0.matchText) == key }
    guard matches.count == 1 else { return nil }
    return matches[0].envelopeID
  }

  func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}

struct PayeeRuleItem {
  var matchText: String
  var envelopeID: UUID
}
