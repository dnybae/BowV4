import Foundation

enum AppStoreLink {
  // Placeholder until Bow has an App Store Connect record. Replace with the numeric Apple ID.
  static let appID = "0000000000"

  static var writeReview: URL {
    URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
  }
}
