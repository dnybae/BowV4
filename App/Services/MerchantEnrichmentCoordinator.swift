import Foundation
import SwiftData

@MainActor
final class MerchantEnrichmentCoordinator {
  static let shared = MerchantEnrichmentCoordinator()
  private var isRunning = false

  private init() {}

  func run(container: ModelContainer, maxLookups: Int = 20) async {
    guard !isRunning, !UserDefaults.standard.bool(forKey: "bow.demoMode") else { return }
    isRunning = true
    defer { isRunning = false }

    let context = ModelContext(container)
    var payees: [BudgetPayee]
    let transactions: [BudgetTransaction]
    do {
      payees = try context.fetch(FetchDescriptor<BudgetPayee>())
      var request = FetchDescriptor<BudgetTransaction>(
        predicate: #Predicate {
          ($0.sourceRaw == "simplefin" || $0.sourceRaw == "bankFile")
            && $0.kindRaw == "expense"
            && $0.merchantDomain == nil
            && $0.brandLookupAttemptedAt == nil
        },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
      )
      request.fetchLimit = 200
      transactions = try context.fetch(request)
    } catch { return }

    var processed: Set<String> = []
    var lookups = 0
    for transaction in transactions {
      let descriptor = (transaction.bankDescription ?? transaction.payee)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let key = PayeeDirectory.key(descriptor)
      guard !key.isEmpty, processed.insert(key).inserted else { continue }
      let group = transactions.filter {
        PayeeDirectory.key(($0.bankDescription ?? $0.payee)) == key
      }

      let matchedPayee = PayeeDirectory.matchingPayee(for: descriptor, payees: payees)
      if let payee = matchedPayee, let domain = payee.merchantDomain {
        apply(payee: payee, domain: domain, to: group)
        try? context.save()
        continue
      }

      guard BrandLookupClient.isConfigured, shouldIdentify(descriptor), lookups < maxLookups else {
        continue
      }
      lookups += 1
      do {
        guard let brand = try await BrandLookupClient.identify(descriptor) else {
          for item in group { item.brandLookupAttemptedAt = Date() }
          try? context.save()
          continue
        }
        let payee: BudgetPayee
        if let existing = matchedPayee {
          existing.merchantDomain = brand.domain
          payee = existing
        } else if let existing = payees.first(where: { $0.merchantDomain == brand.domain }) {
          payee = existing
        } else if let existing = PayeeDirectory.matchingPayee(for: brand.name, payees: payees) {
          guard existing.merchantDomain == nil || existing.merchantDomain == brand.domain else {
            for item in group { item.brandLookupAttemptedAt = Date() }
            try? context.save()
            continue
          }
          existing.merchantDomain = brand.domain
          payee = existing
        } else {
          payee = BudgetPayee(
            name: brand.name, exactMatchText: descriptor,
            merchantDomain: brand.domain, brandDescription: brand.description
          )
          context.insert(payee)
          payees.append(payee)
        }
        if payee.brandDescription == nil { payee.brandDescription = brand.description }
        if payee.exactMatchText.isEmpty && PayeeDirectory.key(payee.name) != key {
          payee.exactMatchText = descriptor
        }
        apply(payee: payee, domain: brand.domain, to: group)
        try context.save()
      } catch {
        // A network or quota failure remains retryable on a later run.
        break
      }
    }
  }

  private func apply(payee: BudgetPayee, domain: String, to transactions: [BudgetTransaction]) {
    for transaction in transactions {
      if transaction.bankDescription == nil { transaction.bankDescription = transaction.payee }
      transaction.payee = payee.name
      transaction.merchantDomain = domain
      if transaction.envelopeID == nil && transaction.kind == .expense {
        transaction.envelopeID = payee.defaultEnvelopeID
      }
    }
  }

  private func shouldIdentify(_ descriptor: String) -> Bool {
    guard descriptor.count >= 3 && descriptor.count <= 500 else { return false }
    let upper = descriptor.uppercased()
    return !["TRANSFER", "ZELLE", "VENMO", "CASH APP", "ATM ", "CHECK "]
      .contains(where: upper.hasPrefix)
  }
}
