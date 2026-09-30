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

  /// Folds one payee into another. The source's name and bank names become bank names of the
  /// target, its transactions and schedules take the target's name, and any settings the
  /// target doesn't have yet carry over.
  func merge(sourceKey: String, sourceName: String, into targetKey: String, targetName: String) throws {
    guard sourceKey != targetKey else { return }
    let context = ModelContext(modelContainer)
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let source = payees.first { PayeeDirectory.key($0.name) == sourceKey }
    let target: BudgetPayee
    if let existing = payees.first(where: { PayeeDirectory.key($0.name) == targetKey }) {
      target = existing
    } else {
      target = BudgetPayee(name: targetName)
      context.insert(target)
    }
    target.bankNames = target.bankNames + [source?.name ?? sourceName] + (source?.bankNames ?? [])
    if let source {
      if target.defaultEnvelopeID == nil { target.defaultEnvelopeID = source.defaultEnvelopeID }
      if target.notes.isEmpty {
        target.notes = source.notes
      } else if !source.notes.isEmpty {
        target.notes += "\n\n" + source.notes
      }
      if target.merchantDomain == nil { target.merchantDomain = source.merchantDomain }
      if target.logoSource == .system && source.logoSource != .system {
        target.logoSource = source.logoSource
        target.customLogoData = source.customLogoData
        if source.logoSource == .logoDev { target.merchantDomain = source.merchantDomain }
      }
      context.delete(source)
    }
    try context.save()
    try renameHistory(from: [sourceKey], to: target.name)
  }

  func entries() throws -> [PayeeDirectory.Entry] {
    let context = ModelContext(modelContainer)
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    var result: [String: PayeeDirectory.Entry] = [:]
    let aliases = PayeeDirectory.aliases(for: payees)
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
    let aliases = PayeeDirectory.aliases(for: try ModelContext(modelContainer).fetch(FetchDescriptor<BudgetPayee>()))
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
      descriptor.propertiesToFetch = [\.payee, \.date, \.amountMinor, \.accountID, \.kindRaw, \.envelopeID]
      let batch = try ModelContext(modelContainer).fetch(descriptor)
      for transaction in batch {
        let normalized = PayeeDirectory.key(transaction.payee)
        guard (aliases[normalized] ?? normalized) == payeeKey else { continue }
        records.append(PayeeActivity.Record(
          date: transaction.date, amountMinor: transaction.amountMinor,
          accountID: transaction.accountID, kind: transaction.kind,
          envelopeID: transaction.envelopeID
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
    let aliases = PayeeDirectory.aliases(for: try ModelContext(modelContainer).fetch(FetchDescriptor<BudgetPayee>()))
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
}

struct PayeeLastUsed: Sendable {
  var accountID: UUID
  var envelopeID: UUID?
}
