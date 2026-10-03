import Foundation

/// Funding toward this month's target. Spending never changes this progress.
struct EnvelopeFundingProgress {
  private(set) var assignedMinor: Int64
  private(set) var targetMinor: Int64

  init?(assignedMinor: Int64, targetMinor: Int64?) {
    guard let targetMinor, targetMinor > 0 else { return nil }
    self.assignedMinor = max(0, assignedMinor)
    self.targetMinor = targetMinor
  }

  var remainingMinor: Int64 { max(0, targetMinor - assignedMinor) }
  var isFullyFunded: Bool { remainingMinor == 0 }
  var fraction: Double { min(1, Double(assignedMinor) / Double(targetMinor)) }
}
