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
      for name in [payee.name, payee.exactMatchText] {
        let key = PayeeDirectory.key(name)
        if !key.isEmpty && appearances[key] == nil {
          appearances[key] = appearance
        }
      }
    }
  }

  func appearance(for name: String) -> PayeeLogoAppearance? {
    appearances[PayeeDirectory.key(name)]
  }
}

struct PayeeLogoAppearance {
  var name: String
  var source: PayeeLogoSource
  var domain: String?
  var imageData: Data?
}

extension EnvironmentValues {
  @Entry var payeeLogoDirectory = PayeeLogoDirectory()
}
