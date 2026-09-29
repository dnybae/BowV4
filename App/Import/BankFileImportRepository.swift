import Foundation
import SwiftData

@ModelActor
actor BankFileImportRepository {
  func save(
    proposals: [BankImportProposal],
    accountID: UUID
  ) throws -> BankFileImportSummary {
    let context = ModelContext(modelContainer)
    var accountRequest = FetchDescriptor<BudgetAccount>(
      predicate: #Predicate { $0.id == accountID }
    )
    accountRequest.fetchLimit = 1
    guard let account = try context.fetch(accountRequest).first else {
      throw BankFileImportError.previewChanged
    }
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    var existingKeys: Set<String> = []
    var offset = 0
    while true {
      try Task.checkCancellation()
      var request = FetchDescriptor<BudgetTransaction>(sortBy: [SortDescriptor(\.id)])
      request.fetchLimit = 512
      request.fetchOffset = offset
      request.propertiesToFetch = [\.id, \.externalKey]
      let batch = try ModelContext(modelContainer).fetch(request)
      for transaction in batch {
        if let key = transaction.externalKey { existingKeys.insert(key) }
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    for record in try context.fetch(FetchDescriptor<SimpleFINImportRecord>()) {
      existingKeys.insert(record.remoteKey)
    }
    return try BankFileImportService().save(
      proposals: proposals,
      account: account, existingKeys: existingKeys,
      payees: payees, envelopes: envelopes, in: context
    )
  }
}
