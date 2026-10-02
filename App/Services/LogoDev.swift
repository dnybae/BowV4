import Foundation

enum LogoDev {
  private static var publishableKey: String? {
    let value = Bundle.main.object(forInfoDictionaryKey: "LogoDevPublishableKey") as? String
    guard let value, value.hasPrefix("pk_") else { return nil }
    return value
  }

  /// - Parameter userRequested: The person is searching for a logo themselves, so a name may be
  ///   sent and the Merchant logos setting doesn't apply. Automatic lookups only ever send a
  ///   website domain, and only while Merchant logos is on.
  static func logoURL(domain: String?, merchantName: String, userRequested: Bool = false) -> URL? {
    guard let publishableKey else { return nil }
    guard userRequested || MerchantLogoSettings.isEnabled else { return nil }
    let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let knownDomain = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let inferredDomain = name.lowercased()
    let resolvedDomain = isDomain(knownDomain) ? knownDomain
      : (isDomain(inferredDomain) ? inferredDomain : nil)
    guard resolvedDomain != nil || (userRequested && !name.isEmpty) else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "img.logo.dev"
    if let resolvedDomain {
      components.path = "/\(resolvedDomain)"
    } else {
      var pathCharacters = CharacterSet.alphanumerics
      pathCharacters.insert(charactersIn: "-._~")
      guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: pathCharacters) else {
        return nil
      }
      components.percentEncodedPath = "/name/\(encodedName)"
    }
    components.queryItems = [
      URLQueryItem(name: "token", value: publishableKey),
      URLQueryItem(name: "size", value: "256"),
      URLQueryItem(name: "format", value: "png"),
      URLQueryItem(name: "fallback", value: "404")
    ]
    return components.url
  }

  private static func isDomain(_ value: String) -> Bool {
    value.contains(".") && value.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil
  }
}

/// Settings › Merchant logos. On by default; off stops every automatic logo request.
enum MerchantLogoSettings {
  static let key = "bow.showsMerchantLogos"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
  }
}
