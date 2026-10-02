import Foundation
import SwiftData

@Model
final class BudgetAccount {
  var id: UUID = UUID()
  var name: String = ""
  var kindRaw: String = BudgetAccountKind.cash.rawValue
  var typeRaw: String? = nil
  var currencyCode: String = "USD"
  var openingBalanceMinor: Int64 = 0
  var note: String = ""
  /// The start of the day the starting balance is as of. Earlier transactions are history.
  var openedAt: Date = Date()
  /// Set when the account is closed: it keeps its history but leaves pickers and totals.
  var closedAt: Date? = nil
  var lastReconciledAt: Date? = nil
  var lastReconciledBalanceMinor: Int64? = nil
  var debtGoalStartMinor: Int64? = nil
  var debtGoalDate: Date? = nil
  var debtMonthlyTargetMinor: Int64? = nil
  var paymentEnvelopeID: UUID? = nil
  var institutionName: String? = nil
  var institutionDomain: String? = nil
  /// Nil follows the bank identity; explicit choices always survive sync.
  var logoSourceRaw: String? = nil
  var logoDomain: String? = nil
  var logoLookupName: String? = nil
  @Attribute(.externalStorage) var customLogoData: Data? = nil

  var logoSettings: AccountLogoSettings {
    get {
      AccountLogoSettings(source: logoSourceRaw.flatMap(PayeeLogoSource.init(rawValue:)),
                          domain: logoDomain ?? "", lookupName: logoLookupName ?? "", imageData: customLogoData)
    }
    set {
      logoSourceRaw = newValue.source?.rawValue
      logoDomain = newValue.domain
      logoLookupName = newValue.lookupName
      customLogoData = newValue.imageData
    }
  }

  var logoAppearance: PayeeLogoAppearance {
    logoSettings.appearance(institutionName: institutionName, institutionDomain: institutionDomain)
  }

  var kind: BudgetAccountKind {
    BudgetAccountKind(rawValue: kindRaw) ?? .cash
  }

  var accountType: BudgetAccountType {
    BudgetAccountType(rawValue: typeRaw ?? "") ?? .defaultType(for: kind)
  }

  init(name: String, kind: BudgetAccountKind, currencyCode: String, openingBalanceMinor: Int64,
       type: BudgetAccountType? = nil, note: String = "") {
    self.name = name
    self.kindRaw = kind.rawValue
    self.typeRaw = type?.rawValue
    self.currencyCode = currencyCode
    self.openingBalanceMinor = openingBalanceMinor
    self.note = note
    if kind == .credit && openingBalanceMinor < 0 {
      self.debtGoalStartMinor = -openingBalanceMinor
    }
  }
}
