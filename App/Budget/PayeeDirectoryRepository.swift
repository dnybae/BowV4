import Foundation
import SwiftData

@ModelActor
actor PayeeDirectoryRepository {
  func renameHistory(from oldKeys: Set<String>, to newName: String) throws {
    var offset = 0
    while true {
      try Task.checkCancellation()
      let context = ModelContext(modelContainer)
      var descriptor = FetchDescriptor<BudgetTransaction>(sortBy: [SortDescriptor(\.id)])
      descriptor.fetchLimit = 256
      descriptor.fetchOffset = offset
      let batch = try context.fetch(descriptor)
      for transaction in batch where oldKeys.contains(PayeeDirectory.key(transaction.payee)) {
        if transaction.payee != newName { transaction.merchantDomain = nil }
        transaction.payee = newName
      }
      if context.hasChanges { try context.save() }
      offset += batch.count
      if batch.count < 256 { break }
    }
    let context = ModelContext(modelContainer)
    for schedule in try context.fetch(FetchDescriptor<BudgetSchedule>())
      where oldKeys.contains(PayeeDirectory.key(schedule.payee)) {
      schedule.payee = newName
    }
    if context.hasChanges { try context.save() }
  }

  func entries() throws -> [PayeeDirectory.Entry] {
    let context = ModelContext(modelContainer)
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    var result: [String: PayeeDirectory.Entry] = [:]
    let aliases = Self.aliases(for: payees)
    for payee in payees {
      let canonical = PayeeDirectory.key(payee.name)
      guard !canonical.isEmpty else { continue }
      result[canonical] = PayeeDirectory.Entry(
        name: payee.name, key: canonical, ruleID: payee.id,
        transactionCount: 0, scheduleCount: 0, isTransferOnly: false
      )
    }
    var offset = 0
    while true {
      try Task.checkCancellation()
      var descriptor = FetchDescriptor<BudgetTransaction>(sortBy: [SortDescriptor(\.id)])
      descriptor.fetchLimit = 512
      descriptor.fetchOffset = offset
      descriptor.propertiesToFetch = [\.id, \.payee, \.kindRaw]
      let batch = try ModelContext(modelContainer).fetch(descriptor)
      for transaction in batch {
        let normalized = PayeeDirectory.key(transaction.payee)
        let key = aliases[normalized] ?? normalized
        guard !key.isEmpty else { continue }
        var entry = result[key] ?? PayeeDirectory.Entry(
          name: transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines),
          key: key, ruleID: nil, transactionCount: 0,
          scheduleCount: 0, isTransferOnly: true
        )
        entry.transactionCount += 1
        if transaction.kind != .transfer { entry.isTransferOnly = false }
        result[key] = entry
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    for schedule in schedules {
      let normalized = PayeeDirectory.key(schedule.payee)
      let key = aliases[normalized] ?? normalized
      guard !key.isEmpty else { continue }
      var entry = result[key] ?? PayeeDirectory.Entry(
        name: schedule.payee.trimmingCharacters(in: .whitespacesAndNewlines),
        key: key, ruleID: nil, transactionCount: 0,
        scheduleCount: 0, isTransferOnly: false
      )
      entry.scheduleCount += 1
      entry.isTransferOnly = false
      result[key] = entry
    }
    return result.values.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  /// Summarizes every non-transfer transaction recorded under a payee or its bank description.
  func activity(for payeeKey: String) throws -> PayeeActivity? {
    let aliases = Self.aliases(for: try ModelContext(modelContainer).fetch(FetchDescriptor<BudgetPayee>()))
    let transferKind = BudgetTransactionKind.transfer.rawValue
    let adjustmentSource = BudgetTransaction.balanceAdjustmentSource
    var records: [PayeeActivity.Record] = []
    var offset = 0
    while true {
      try Task.checkCancellation()
      var descriptor = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate { $0.kindRaw != transferKind && $0.sourceRaw != adjustmentSource },
        sortBy: [SortDescriptor(\.id)]
      )
      descriptor.fetchLimit = 512
      descriptor.fetchOffset = offset
      descriptor.propertiesToFetch = [\.payee, \.date, \.amountMinor, \.accountID, \.kindRaw]
      let batch = try ModelContext(modelContainer).fetch(descriptor)
      for transaction in batch {
        let normalized = PayeeDirectory.key(transaction.payee)
        guard (aliases[normalized] ?? normalized) == payeeKey else { continue }
        records.append(PayeeActivity.Record(
          date: transaction.date, amountMinor: transaction.amountMinor,
          accountID: transaction.accountID, kind: transaction.kind
        ))
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    return PayeeActivity.make(from: records)
  }

  /// The account and envelope from the most recent transaction of this kind with a payee.
  func lastUsed(
    payee name: String, kind: BudgetTransactionKind, excluding excludedID: UUID? = nil
  ) throws -> PayeeLastUsed? {
    let aliases = Self.aliases(for: try ModelContext(modelContainer).fetch(FetchDescriptor<BudgetPayee>()))
    let normalizedName = PayeeDirectory.key(name)
    let payeeKey = aliases[normalizedName] ?? normalizedName
    guard !payeeKey.isEmpty else { return nil }
    let kindRaw = kind.rawValue
    let adjustmentSource = BudgetTransaction.balanceAdjustmentSource
    var offset = 0
    while true {
      try Task.checkCancellation()
      var descriptor = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate { $0.kindRaw == kindRaw && $0.sourceRaw != adjustmentSource },
        sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
      )
      descriptor.fetchLimit = 256
      descriptor.fetchOffset = offset
      let batch = try ModelContext(modelContainer).fetch(descriptor)
      if let match = batch.first(where: { transaction in
        let normalized = PayeeDirectory.key(transaction.payee)
        return transaction.id != excludedID && (aliases[normalized] ?? normalized) == payeeKey
      }) {
        return PayeeLastUsed(accountID: match.accountID, envelopeID: match.envelopeID)
      }
      offset += batch.count
      if batch.count < 256 { return nil }
    }
  }

  private static func aliases(for payees: [BudgetPayee]) -> [String: String] {
    var aliases: [String: String] = [:]
    for payee in payees {
      let canonical = PayeeDirectory.key(payee.name)
      guard !canonical.isEmpty else { continue }
      let exact = PayeeDirectory.key(payee.exactMatchText)
      if aliases[canonical] == nil { aliases[canonical] = canonical }
      if !exact.isEmpty && aliases[exact] == nil { aliases[exact] = canonical }
    }
    return aliases
  }
}

struct PayeeLastUsed: Sendable {
  var accountID: UUID
  var envelopeID: UUID?
}
