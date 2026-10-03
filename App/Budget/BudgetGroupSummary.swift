import Foundation

/// A collapsed group keeps its signed total and counts each item's existing status separately.
/// A positive group balance must never hide an overspent envelope or a short card payment.
struct BudgetGroupSummary {
  var count = 0
  var availableMinor: Int64 = 0
  var overspentCount = 0
  var needsFundingCount = 0
  var fundedCount = 0
  var emptyCount = 0

  var needsAttention: Bool { overspentCount > 0 || needsFundingCount > 0 }

  init(items: [Item]) {
    count = items.count
    for item in items {
      availableMinor += item.availableMinor
      switch item.status.state {
      case .over: overspentCount += 1
      case .needs: needsFundingCount += 1
      case .funded: fundedCount += 1
      case .empty: emptyCount += 1
      }
    }
  }

  struct Item {
    var availableMinor: Int64
    var status: EnvelopeStatus
  }
}
