import Foundation
import SwiftData

@ModelActor
actor SimpleFINImportRepository {
  func importTransactions(_ accounts: [SimpleFINRemoteAccount]) throws -> SimpleFINSyncSummary {
    let context = ModelContext(modelContainer)
    let summary = try SimpleFINSyncCoordinator.importTransactionsOffMain(accounts, in: context)
    try context.save()
    return summary
  }
}
