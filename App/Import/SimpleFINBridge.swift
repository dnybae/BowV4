import Foundation

/// SimpleFIN Bridge's website, where people sign up, get setup tokens, and manage their banks.
enum SimpleFINBridge {
  static let home = URL(string: "https://beta-bridge.simplefin.org")!
  /// Connected banks, reconnecting a bank, and billing.
  static let account = URL(string: "https://beta-bridge.simplefin.org/my-account")!
}
