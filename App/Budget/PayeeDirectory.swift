import Foundation

struct PayeeDirectory {
  struct Entry: Identifiable {
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

  static func ruleItems(payees: [BudgetPayee], validEnvelopeIDs: Set<UUID>) -> [PayeeRuleItem] {
    payees.flatMap { payee -> [PayeeRuleItem] in
      guard let id = payee.defaultEnvelopeID, validEnvelopeIDs.contains(id) else { return [] }
      let name = key(payee.name)
      let exact = key(payee.exactMatchText)
      var items = [PayeeRuleItem(matchText: payee.name, envelopeID: id)]
      if !exact.isEmpty && exact != name {
        items.append(PayeeRuleItem(matchText: payee.exactMatchText, envelopeID: id))
      }
      return items
    }
  }

  static func canonicalKey(for name: String, payees: [BudgetPayee]) -> String {
    let normalized = key(name)
    guard !normalized.isEmpty else { return "" }
    if let payee = payees.first(where: {
      key($0.name) == normalized
        || (!key($0.exactMatchText).isEmpty && key($0.exactMatchText) == normalized)
    }) {
      return key(payee.name)
    }
    return normalized
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
        isTransferOnly: true
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
      transaction.payee = newName
    }
    for schedule in schedules where canonicalKey(for: schedule.payee, payees: payees) == oldKey {
      schedule.payee = newName
    }
  }
}
