import Foundation
import SwiftData

@Model
final class BudgetPayee {
  var id: UUID = UUID()
  var name: String = ""
  var defaultEnvelopeID: UUID? = nil
  var exactMatchText: String = ""
  var merchantDomain: String? = nil
  var notes: String = ""
  var logoSourceRaw: String = PayeeLogoSource.system.rawValue
  @Attribute(.externalStorage) var customLogoData: Data? = nil

  var logoSource: PayeeLogoSource {
    get { PayeeLogoSource(rawValue: logoSourceRaw) ?? .system }
    set { logoSourceRaw = newValue.rawValue }
  }

  init(
    name: String, defaultEnvelopeID: UUID? = nil, exactMatchText: String = "",
    merchantDomain: String? = nil
  ) {
    self.name = name
    self.defaultEnvelopeID = defaultEnvelopeID
    self.exactMatchText = exactMatchText
    self.merchantDomain = merchantDomain
  }
}
