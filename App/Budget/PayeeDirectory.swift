import Foundation

struct PayeeDirectory {
  struct Entry: Identifiable, Sendable {
    var name: String
    var key: String
    var ruleID: UUID?
    var transactionCount: Int
    var scheduleCount: Int
    var isTransferOnly: Bool

    var id: String { key }
  }

  static func key(_ name: String) -> String {
    PayeeRuleMatcher().normalized(name)
  }

  /// Every normalized name that files under a payee: its own name, then its bank names.
  static func matchKeys(for payee: BudgetPayee) -> [String] {
    ([payee.name] + payee.bankNames).map(key).filter { !$0.isEmpty }
  }

  /// Maps each payee name and bank name to the payee's canonical key. The first payee wins a conflict.
  static func aliases(for payees: [BudgetPayee]) -> [String: String] {
    var aliases: [String: String] = [:]
    for payee in payees {
      let canonical = key(payee.name)
      guard !canonical.isEmpty else { continue }
      for matchKey in matchKeys(for: payee) where aliases[matchKey] == nil {
        aliases[matchKey] = canonical
      }
    }
    return aliases
  }

  static func ruleItems(payees: [BudgetPayee], validEnvelopeIDs: Set<UUID>) -> [PayeeRuleItem] {
    payees.flatMap { payee -> [PayeeRuleItem] in
      guard let id = payee.defaultEnvelopeID, validEnvelopeIDs.contains(id) else { return [] }
      return ([payee.name] + payee.bankNames).map { PayeeRuleItem(matchText: $0, envelopeID: id) }
    }
  }

  static func canonicalKey(for name: String, payees: [BudgetPayee]) -> String {
    let normalized = key(name)
    guard !normalized.isEmpty else { return "" }
    return matchingPayee(for: name, payees: payees).map { key($0.name) } ?? normalized
  }

  static func matchingPayee(for name: String, payees: [BudgetPayee]) -> BudgetPayee? {
    let normalized = key(name)
    guard !normalized.isEmpty else { return nil }
    return payees.first { matchKeys(for: $0).contains(normalized) }
  }

  /// Whether two names refer to the same payee, directly or through a saved bank name.
  static func isSamePayee(_ first: String, _ second: String, payees: [BudgetPayee]) -> Bool {
    let firstKey = canonicalKey(for: first, payees: payees)
    return !firstKey.isEmpty && firstKey == canonicalKey(for: second, payees: payees)
  }

  static func logoDomain(for name: String, transactionDomain: String?, payees: [BudgetPayee]) -> String? {
    if let payee = matchingPayee(for: name, payees: payees) { return payee.merchantDomain }
    return transactionDomain
  }

  static func entries(
    payees: [BudgetPayee],
    transactions: [BudgetTransaction],
    schedules: [BudgetSchedule]
  ) -> [Entry] {
    var entries: [String: Entry] = [:]
    for payee in payees {
      let canonical = key(payee.name)
      guard !canonical.isEmpty else { continue }
      entries[canonical] = Entry(
        name: payee.name,
        key: canonical,
        ruleID: payee.id,
        transactionCount: 0,
        scheduleCount: 0,
        isTransferOnly: false
      )
    }
    for transaction in transactions {
      let canonical = canonicalKey(for: transaction.payee, payees: payees)
      guard !canonical.isEmpty else { continue }
      var entry = entries[canonical] ?? Entry(
        name: transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines),
        key: canonical,
        ruleID: nil,
        transactionCount: 0,
        scheduleCount: 0,
        isTransferOnly: true
      )
      entry.transactionCount += 1
      if transaction.kind != .transfer { entry.isTransferOnly = false }
      entries[canonical] = entry
    }
    for schedule in schedules {
      let canonical = canonicalKey(for: schedule.payee, payees: payees)
      guard !canonical.isEmpty else { continue }
      var entry = entries[canonical] ?? Entry(
        name: schedule.payee.trimmingCharacters(in: .whitespacesAndNewlines),
        key: canonical,
        ruleID: nil,
        transactionCount: 0,
        scheduleCount: 0,
        isTransferOnly: false
      )
      entry.scheduleCount += 1
      entry.isTransferOnly = false
      entries[canonical] = entry
    }
    return entries.values.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  static func rename(
    from oldKey: String,
    to newName: String,
    payees: [BudgetPayee],
    transactions: [BudgetTransaction],
    schedules: [BudgetSchedule]
  ) {
    for transaction in transactions where canonicalKey(for: transaction.payee, payees: payees) == oldKey {
      if transaction.payee != newName { transaction.merchantDomain = nil }
      transaction.payee = newName
    }
    for schedule in schedules where canonicalKey(for: schedule.payee, payees: payees) == oldKey {
      schedule.payee = newName
    }
  }
}
