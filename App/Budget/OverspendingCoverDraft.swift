import Foundation
import Observation

/// The donors picked to cover one overspent envelope, before anything is saved.
/// Amounts are always kept between zero and what the donor has, and never past what's still needed.
@Observable
final class OverspendingCoverDraft {
  var envelopeID: UUID
  private(set) var donors: [Donor] = []

  struct Donor: Identifiable, Hashable {
    var bucket: BudgetBucket
    var amountMinor: Int64
    var id: BudgetBucket { bucket }
  }

  init(envelopeID: UUID) {
    self.envelopeID = envelopeID
  }

  func overspentMinor(in snapshot: BudgetSnapshot) -> Int64 {
    max(0, -snapshot.available(for: envelopeID))
  }

  var coveredMinor: Int64 { donors.reduce(0) { $0 + $1.amountMinor } }

  func remainingMinor(in snapshot: BudgetSnapshot) -> Int64 {
    max(0, overspentMinor(in: snapshot) - coveredMinor)
  }

  /// What the donor has before this cover takes anything.
  func availableMinor(of bucket: BudgetBucket, in snapshot: BudgetSnapshot) -> Int64 {
    switch bucket {
    case .readyToAssign: max(0, snapshot.readyToAssignMinor)
    case .envelope(let id): max(0, snapshot.available(for: id))
    case .cardPayment: 0
    }
  }

  /// The most this donor can give: all it has, or what's still needed including its own share.
  func maximumMinor(for bucket: BudgetBucket, in snapshot: BudgetSnapshot) -> Int64 {
    let current = amountMinor(for: bucket)
    let needed = max(0, overspentMinor(in: snapshot) - coveredMinor + current)
    return min(availableMinor(of: bucket, in: snapshot), needed)
  }

  func amountMinor(for bucket: BudgetBucket) -> Int64 {
    donors.first { $0.bucket == bucket }?.amountMinor ?? 0
  }

  func contains(_ bucket: BudgetBucket) -> Bool {
    donors.contains { $0.bucket == bucket }
  }

  /// Adds a donor, pre-filled with as much as it can give toward what's left.
  func add(_ bucket: BudgetBucket, in snapshot: BudgetSnapshot) {
    guard !contains(bucket), bucket != .envelope(envelopeID) else { return }
    let amount = min(availableMinor(of: bucket, in: snapshot), remainingMinor(in: snapshot))
    donors.append(Donor(bucket: bucket, amountMinor: max(0, amount)))
  }

  func setAmount(_ minor: Int64, for bucket: BudgetBucket, in snapshot: BudgetSnapshot) {
    guard let index = donors.firstIndex(where: { $0.bucket == bucket }) else { return }
    donors[index].amountMinor = min(max(0, minor), maximumMinor(for: bucket, in: snapshot))
  }

  func remove(_ bucket: BudgetBucket) {
    donors.removeAll { $0.bucket == bucket }
  }

  /// Keeps every amount valid after the budget changes underneath the draft, such as after a bank sync.
  func clamp(to snapshot: BudgetSnapshot) {
    for donor in donors {
      setAmount(donor.amountMinor, for: donor.bucket, in: snapshot)
    }
  }

  func canSave(in snapshot: BudgetSnapshot) -> Bool {
    coveredMinor > 0 && coveredMinor <= overspentMinor(in: snapshot)
      && donors.allSatisfy { $0.amountMinor <= availableMinor(of: $0.bucket, in: snapshot) }
  }

  var donorAmounts: [BudgetBucket: Int64] {
    Dictionary(donors.filter { $0.amountMinor > 0 }.map { ($0.bucket, $0.amountMinor) }, uniquingKeysWith: +)
  }
}
