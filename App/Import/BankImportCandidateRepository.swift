import Foundation
import SwiftData

struct BankImportCandidateBundle: Sendable {
  var existing: [LocalTransactionCandidate]
  var transfers: [LocalTransactionCandidate]
  var stagedKeys: [String: UUID]
  var uncategorizedManualIDs: Set<UUID>
}

@ModelActor
actor BankImportCandidateRepository {
  func candidates(accountID: UUID, rows: [BankImportRow]) throws -> BankImportCandidateBundle {
    guard let earliest = rows.map(\.date).min(), let latest = rows.map(\.date).max() else {
      return BankImportCandidateBundle(
        existing: [], transfers: [], stagedKeys: [:], uncategorizedManualIDs: []
      )
    }
    let start = earliest.addingTimeInterval(-7 * 86_400)
    let end = latest.addingTimeInterval(7 * 86_400)
    var bundle = BankImportCandidateBundle(
      existing: [], transfers: [], stagedKeys: [:], uncategorizedManualIDs: []
    )
    let records = try ModelContext(modelContainer).fetch(FetchDescriptor<SimpleFINImportRecord>())
    for record in records {
      bundle.stagedKeys[record.remoteKey] = record.id
      if record.localAccountID == accountID && record.bankState == .posted
        && record.status == .review {
        bundle.existing.append(LocalTransactionCandidate(
          id: record.id, accountID: accountID,
          amountMinor: record.amountMinor, date: record.date,
          payee: record.payee, externalKey: record.remoteKey,
          isManual: false
        ))
      }
    }
    var offset = 0
    while true {
      try Task.checkCancellation()
      var request = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate {
          $0.date >= start && $0.date <= end
            && ($0.accountID == accountID || $0.transferAccountID == accountID)
        },
        sortBy: [SortDescriptor(\.id)]
      )
      request.fetchLimit = 512
      request.fetchOffset = offset
      request.propertiesToFetch = [\.id, \.accountID, \.transferAccountID, \.date,
                                   \.amountMinor, \.payee, \.externalKey, \.sourceRaw,
                                   \.kindRaw, \.envelopeID, \.scheduleID]
      let batch = try ModelContext(modelContainer).fetch(request)
      for transaction in batch {
        if transaction.kind == .transfer {
          if transaction.accountID == accountID {
            bundle.transfers.append(LocalTransactionCandidate(
              id: transaction.id, accountID: accountID,
              amountMinor: transaction.amountMinor, date: transaction.date,
              payee: transaction.payee, externalKey: transaction.externalKey,
              isManual: false
            ))
          }
          if transaction.transferAccountID == accountID {
            bundle.transfers.append(LocalTransactionCandidate(
              id: transaction.id, accountID: accountID,
              amountMinor: -transaction.amountMinor, date: transaction.date,
              payee: transaction.payee, externalKey: nil, isManual: false
            ))
          }
        } else if transaction.accountID == accountID {
          if transaction.kind == .expense && transaction.envelopeID == nil
            && transaction.sourceRaw == "manual" {
            bundle.uncategorizedManualIDs.insert(transaction.id)
          }
          bundle.existing.append(LocalTransactionCandidate(
            id: transaction.id, accountID: accountID,
            amountMinor: transaction.amountMinor, date: transaction.date,
            payee: transaction.payee, externalKey: transaction.externalKey,
            isManual: transaction.sourceRaw == "manual",
            envelopeID: transaction.envelopeID,
            scheduleID: transaction.scheduleID
          ))
        }
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    return bundle
  }
}
