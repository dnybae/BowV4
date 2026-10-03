import Foundation

/// Linked and manual describe how accounts are updated, independently of their balance's sign.
struct AccountGroupSummary {
  var count: Int
  var balanceMinor: Int64
  var linkedCount: Int
  var manualCount: Int { count - linkedCount }

  init(accounts: [BudgetAccount], balances: [UUID: Int64], linkedAccountIDs: Set<UUID>) {
    count = accounts.count
    balanceMinor = accounts.reduce(0) { $0 + balances[$1.id, default: 0] }
    linkedCount = accounts.filter { linkedAccountIDs.contains($0.id) }.count
  }
}
