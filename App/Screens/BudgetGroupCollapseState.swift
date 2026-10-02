import Foundation

/// Which Budget groups are collapsed, saved in UserDefaults so it survives relaunches.
/// Views hold it in @State rather than @AppStorage: AppStorage writes don't carry the
/// `withAnimation` transaction, so collapsing would snap instead of animating.
/// Keys are group IDs, plus `creditCardsKey` for the card payments group.
struct BudgetGroupCollapseState: RawRepresentable, Equatable {
  static let creditCardsKey = "credit-card-payments"
  private static let defaultsKey = "budgetCollapsedGroups"

  /// The state last saved with `save()`.
  static var saved: BudgetGroupCollapseState {
    UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? Self()
  }

  var collapsedKeys: Set<String> = []

  init() {}

  init?(rawValue: String) {
    collapsedKeys = Set(rawValue.split(separator: "\n").map(String.init))
  }

  var rawValue: String { collapsedKeys.sorted().joined(separator: "\n") }

  func save() { UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey) }

  func isCollapsed(_ key: String) -> Bool { collapsedKeys.contains(key) }

  mutating func toggle(_ key: String) {
    if collapsedKeys.contains(key) {
      collapsedKeys.remove(key)
    } else {
      collapsedKeys.insert(key)
    }
  }
}
