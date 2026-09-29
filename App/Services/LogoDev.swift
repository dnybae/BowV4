import Foundation

enum LogoDev {
  private static var publishableKey: String? {
    let value = Bundle.main.object(forInfoDictionaryKey: "LogoDevPublishableKey") as? String
    guard let value, value.hasPrefix("pk_") else { return nil }
    return value
  }

  static func logoURL(domain: String?, merchantName: String) -> URL? {
    guard let publishableKey else { return nil }
    let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let knownDomain = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let inferredDomain = name.lowercased()
    let resolvedDomain = isDomain(knownDomain) ? knownDomain
      : (isDomain(inferredDomain) ? inferredDomain : nil)
    guard resolvedDomain != nil || !name.isEmpty else { return nil }

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
      URLQueryItem(name: "size", value: "64"),
      URLQueryItem(name: "format", value: "png"),
      URLQueryItem(name: "fallback", value: "404")
    ]
    return components.url
  }

  private static func isDomain(_ value: String) -> Bool {
    value.contains(".") && value.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil
  }
}
