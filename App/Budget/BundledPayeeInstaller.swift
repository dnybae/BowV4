import Foundation
import SwiftData

/// Installs once per budget so edits, merges, and deletions survive future launches.
@MainActor
enum BundledPayeeInstaller {
  static func installIfNeeded(in container: ModelContainer) throws {
    // Isolate the import from any pending editor changes. The marker and payees save together.
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let profiles = try context.fetch(FetchDescriptor<BudgetProfile>())
    guard !profiles.isEmpty, profiles.allSatisfy({ $0.bundledPayeesVersion < 1 }) else { return }
    var payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    for entry in BundledPayees.entries {
      if let existing = PayeeDirectory.matchingPayee(for: entry.name, payees: payees) {
        if existing.merchantDomain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
          existing.merchantDomain = entry.domain
        }
      } else {
        let payee = BudgetPayee(name: entry.name, merchantDomain: entry.domain)
        payee.logoSource = .logoDev
        context.insert(payee)
        payees.append(payee)
      }
    }
    for profile in profiles { profile.bundledPayeesVersion = 1 }
    try context.save()
  }
}
