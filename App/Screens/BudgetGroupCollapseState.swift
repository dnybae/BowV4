import Foundation

/// Which Budget groups are collapsed, stored in AppStorage so it survives relaunches.
/// Keys are group IDs, plus `creditCardsKey` for the card payments group.
struct BudgetGroupCollapseState: RawRepresentable, Equatable {
  static let creditCardsKey = "credit-card-payments"

  var collapsedKeys: Set<String> = []

  init() {}

  init?(rawValue: String) {
    collapsedKeys = Set(rawValue.split(separator: "\n").map(String.init))
  }

  var rawValue: String { collapsedKeys.sorted().joined(separator: "\n") }

  func isCollapsed(_ key: String) -> Bool { collapsedKeys.contains(key) }

  mutating func toggle(_ key: String) {
    if collapsedKeys.contains(key) {
      collapsedKeys.remove(key)
    } else {
      collapsedKeys.insert(key)
    }
  }
}
