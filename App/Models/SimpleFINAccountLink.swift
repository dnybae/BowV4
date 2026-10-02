import Foundation
import SwiftData

@Model
final class SimpleFINAccountLink {
  #Index<SimpleFINAccountLink>([\.remoteKey], [\.localAccountID])
  var id: UUID = UUID()
  var remoteKey: String = ""
  var name: String = ""
  var currencyCode: String = "USD"
  var localAccountID: UUID? = nil
  var importStartDate: Date? = nil
  var reportedBalance: String? = nil
  var reportedAt: Date? = nil
  var institutionName: String? = nil
  var institutionDomain: String? = nil

  var logoAppearance: PayeeLogoAppearance {
    AccountLogoSettings().appearance(institutionName: institutionName, institutionDomain: institutionDomain)
  }

  func applyInstitution(to account: BudgetAccount) {
    account.institutionName = institutionName
    account.institutionDomain = institutionDomain
  }

  init(remoteKey: String, name: String, currencyCode: String) {
    self.remoteKey = remoteKey
    self.name = name
    self.currencyCode = currencyCode
  }
}
