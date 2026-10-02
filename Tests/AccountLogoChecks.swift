import Foundation
import SwiftData

@main
struct AccountLogoChecks {
  @MainActor static func main() throws {
    let container = try ModelContainer(for: BudgetAccount.self, SimpleFINAccountLink.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let account = BudgetAccount(name: "Household", kind: .cash, currencyCode: "USD", openingBalanceMinor: 0)
    context.insert(account)
    precondition(account.logoAppearance.source == .system)
    let link = SimpleFINAccountLink(remoteKey: "bank|checking", name: "Checking", currencyCode: "USD")
    context.insert(link)
    link.institutionName = "Bank"
    link.institutionDomain = "bank.example"
    link.applyInstitution(to: account)
    precondition(account.logoAppearance.domain == "bank.example")
    precondition(account.logoAppearance.name == "Bank")
    precondition(account.logoAppearance.source == .logoDev)
    account.logoSettings = AccountLogoSettings(source: .logoDev, domain: "chosen.example", lookupName: "Chosen Bank")
    link.institutionDomain = "updated.example"
    link.applyInstitution(to: account)
    precondition(account.logoAppearance.domain == "chosen.example")
    account.logoSettings = AccountLogoSettings(source: .system)
    link.applyInstitution(to: account)
    precondition(account.logoAppearance.source == .system)
    let photo = Data([1, 2, 3])
    account.logoSettings = AccountLogoSettings(source: .custom, imageData: photo)
    link.applyInstitution(to: account)
    try context.save()
    let fresh = ModelContext(container)
    let reloaded = try fresh.fetch(FetchDescriptor<BudgetAccount>()).first!
    precondition(reloaded.logoAppearance.source == .custom)
    precondition(reloaded.logoAppearance.imageData == photo)
    reloaded.logoSettings = AccountLogoSettings()
    precondition(reloaded.logoAppearance.domain == "updated.example")
    // A manually added account's choice must not depend on its display name.
    reloaded.institutionName = nil
    reloaded.institutionDomain = nil
    reloaded.logoSettings = AccountLogoSettings(source: .logoDev, lookupName: "Manual Bank")
    reloaded.name = "Vacation savings"
    precondition(reloaded.logoAppearance.name == "Manual Bank")
    print("Account logo persistence and override checks passed")
  }
}
