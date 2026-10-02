import Foundation

struct AccountLogoSettings: Equatable {
  var source: PayeeLogoSource? = nil
  var domain = ""
  var lookupName = ""
  var imageData: Data? = nil

  func appearance(institutionName: String?, institutionDomain: String?) -> PayeeLogoAppearance {
    PayeeLogoAppearance(
      name: source == nil ? (institutionName ?? "") : lookupName,
      source: source ?? ((institutionName != nil || institutionDomain != nil) ? .logoDev : .system),
      domain: source == nil ? institutionDomain : domain,
      imageData: imageData
    )
  }
}
