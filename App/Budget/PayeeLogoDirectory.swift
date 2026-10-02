import Foundation
import SwiftUI

struct PayeeLogoDirectory {
  private var appearances: [String: PayeeLogoAppearance] = [:]

  init(payees: [BudgetPayee] = []) {
    for payee in payees {
      let appearance = PayeeLogoAppearance(
        name: payee.name,
        source: payee.logoSource,
        domain: payee.merchantDomain,
        imageData: payee.customLogoData
      )
      for key in PayeeDirectory.matchKeys(for: payee) {
        if appearances[key] == nil {
          appearances[key] = appearance
        }
      }
    }
  }

  func appearance(for name: String) -> PayeeLogoAppearance? {
    appearances[PayeeDirectory.key(name)]
  }
}

extension EnvironmentValues {
  @Entry var payeeLogoDirectory = PayeeLogoDirectory()
}

extension BudgetPayee {
  /// Everything the logo directory reads, so it's rebuilt only when one of these changes.
  var logoSignature: String {
    ([id.uuidString, name, logoSourceRaw, merchantDomain ?? "", String(customLogoData?.count ?? 0)]
      + bankNames).joined(separator: "|")
  }
}
