import Foundation

enum AppStoreLink {
  /// Bow's numeric Apple ID, once its App Store Connect record exists. Until then there's
  /// nothing to review, so the review link is hidden.
  static let appID: String? = nil

  static var writeReview: URL? {
    appID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
  }
}

enum SupportLink {
  static let address = "hello@bowbudget.com"
  static let privacyPolicy = URL(string: "https://bowbudget.com/privacy")!
  static let terms = URL(string: "https://bowbudget.com/terms")!

  static func email(subject: String) -> URL {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = address
    components.queryItems = [URLQueryItem(name: "subject", value: subject)]
    return components.url ?? URL(string: "mailto:\(address)")!
  }
}
