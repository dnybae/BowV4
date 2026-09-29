import Foundation
import SwiftData

struct BankImportCandidateBundle: Sendable {
  var existing: [LocalTransactionCandidate]
  var transfers: [LocalTransactionCandidate]
}

@ModelActor
actor BankImportCandidateRepository {
  func candidates(accountID: UUID, rows: [BankImportRow]) throws -> BankImportCandidateBundle {
    guard let earliest = rows.map(\.date).min(), let latest = rows.map(\.date).max() else {
      return BankImportCandidateBundle(existing: [], transfers: [])
    }
    let start = earliest.addingTimeInterval(-7 * 86_400)
    let end = latest.addingTimeInterval(7 * 86_400)
    var bundle = BankImportCandidateBundle(existing: [], transfers: [])
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
                                   \.amountMinor, \.payee, \.externalKey, \.sourceRaw, \.kindRaw]
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
          bundle.existing.append(LocalTransactionCandidate(
            id: transaction.id, accountID: accountID,
            amountMinor: transaction.amountMinor, date: transaction.date,
            payee: transaction.payee, externalKey: transaction.externalKey,
            isManual: transaction.sourceRaw == "manual"
          ))
        }
      }
      offset += batch.count
      if batch.count < 512 { break }
    }
    return bundle
  }
}
