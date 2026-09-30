import Foundation
import SwiftData

@Model
final class BudgetPayee {
  var id: UUID = UUID()
  var name: String = ""
  var defaultEnvelopeID: UUID? = nil
  /// The original single bank description. Read through `bankNames`, which folds it in.
  var exactMatchText: String = ""
  var extraBankNames: [String] = []
  var merchantDomain: String? = nil
  var notes: String = ""
  var logoSourceRaw: String = PayeeLogoSource.system.rawValue
  @Attribute(.externalStorage) var customLogoData: Data? = nil

  var logoSource: PayeeLogoSource {
    get { PayeeLogoSource(rawValue: logoSourceRaw) ?? .system }
    set { logoSourceRaw = newValue.rawValue }
  }

  /// Bank descriptions that should be filed under this payee, without duplicates or the payee's own name.
  var bankNames: [String] {
    get { Self.cleanedBankNames([exactMatchText] + extraBankNames, excluding: name) }
    set {
      exactMatchText = ""
      extraBankNames = Self.cleanedBankNames(newValue, excluding: name)
    }
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

  static func cleanedBankNames(_ names: [String], excluding payeeName: String) -> [String] {
    var seen: Set<String> = [PayeeDirectory.key(payeeName)]
    var result: [String] = []
    for name in names {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = PayeeDirectory.key(trimmed)
      guard !key.isEmpty, seen.insert(key).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }
}
