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
