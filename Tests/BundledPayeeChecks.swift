import Foundation
import SwiftData

@main
struct BundledPayeeChecks {
  @MainActor
  static func main() throws {
    let container = try ModelContainer(
      for: BudgetProfile.self, BudgetPayee.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    try BundledPayeeInstaller.installIfNeeded(in: container)
    let initialCount = try context.fetchCount(FetchDescriptor<BudgetPayee>())
    precondition(initialCount == 0)

    context.insert(BudgetProfile(currencyCode: "USD"))
    let existing = BudgetPayee(name: "  WALMART  ", merchantDomain: "my.walmart.com")
    existing.notes = "Keep my notes"
    existing.logoSource = .custom
    existing.customLogoData = Data([1, 2, 3])
    context.insert(existing)
    let alias = BudgetPayee(name: "My coffee shop")
    alias.bankNames = ["Starbucks"]
    context.insert(alias)
    try context.save()
    try BundledPayeeInstaller.installIfNeeded(in: container)

    let check = ModelContext(container)
    let payees = try check.fetch(FetchDescriptor<BudgetPayee>())
    precondition(payees.count == 176)
    precondition(Set(BundledPayees.entries.map { PayeeDirectory.key($0.name) }).count == 176)
    let walmart = payees.first { $0.id == existing.id }!
    precondition(walmart.merchantDomain == "my.walmart.com")
    precondition(walmart.logoSource == .custom && walmart.customLogoData == Data([1, 2, 3]))
    precondition(walmart.notes == "Keep my notes")
    let coffee = payees.first { $0.id == alias.id }!
    precondition(coffee.merchantDomain == "starbucks.com" && coffee.logoSource == .system)
    for entry in BundledPayees.entries where entry.name != "Walmart" && entry.name != "Starbucks" {
      let payee = payees.first { $0.name == entry.name }!
      precondition(payee.merchantDomain == entry.domain && payee.logoSource == .logoDev)
    }
    // Services sharing a domain remain separate payees.
    precondition(payees.filter { $0.merchantDomain == "apple.com" }.count == 3)
    let amazon = payees.first { $0.name == "Amazon" }!
    check.delete(amazon)
    coffee.merchantDomain = nil
    try check.save()
    try BundledPayeeInstaller.installIfNeeded(in: container)
    let finalContext = ModelContext(container)
    let finalPayees = try finalContext.fetch(FetchDescriptor<BudgetPayee>())
    precondition(finalPayees.count == 175)
    precondition(finalPayees.first { $0.id == alias.id }!.merchantDomain == nil)
    print("Bundled payee checks passed")
  }
}
