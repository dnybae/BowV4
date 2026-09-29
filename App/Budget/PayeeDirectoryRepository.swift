import Foundation
import SwiftData

@ModelActor
actor PayeeDirectoryRepository {
  func entries() throws -> [PayeeDirectory.Entry] {
    let context = ModelContext(modelContainer)
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    var result: [String: PayeeDirectory.Entry] = [:]
    var aliases: [String: String] = [:]
    for payee in payees {
      let canonical = PayeeDirectory.key(payee.name)
      guard !canonical.isEmpty else { continue }
      let exact = PayeeDirectory.key(payee.exactMatchText)
      if aliases[canonical] == nil { aliases[canonical] = canonical }
      if !exact.isEmpty && aliases[exact] == nil { aliases[exact] = canonical }
      result[canonical] = PayeeDirectory.Entry(
        name: payee.name, key: canonical, ruleID: payee.id,
        transactionCount: 0, scheduleCount: 0, isTransferOnly: true
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
}
