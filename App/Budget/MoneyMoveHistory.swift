import Foundation

/// One month of money moved in and out of an envelope or a card payment, seen from that bucket.
struct MoneyMoveHistory {
  var subject: BudgetBucket
  var month: Date
  var calendar: Calendar = .current

  func moves(
    allocations: [BudgetAllocation], envelopes: [BudgetEnvelope], accounts: [BudgetAccount]
  ) -> [MoneyMoveEntry] {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
    return allocations.compactMap { allocation in
      guard interval.contains(allocation.date) else { return nil }
      let source = Self.bucket(envelopeID: allocation.sourceEnvelopeID, cardID: allocation.sourceCardID)
      let target = Self.bucket(envelopeID: allocation.targetEnvelopeID, cardID: allocation.targetCardID)
      let isIn: Bool
      if target == subject { isIn = true } else if source == subject { isIn = false } else { return nil }
      let other = isIn ? source : target
      return MoneyMoveEntry(
        id: allocation.id, date: allocation.date, createdAt: allocation.createdAt, isIn: isIn,
        counterpart: Self.name(of: other, envelopes: envelopes, accounts: accounts),
        amountMinor: allocation.amountMinor
      )
    }
    .sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
  }

  func count(allocations: [BudgetAllocation]) -> Int {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
    return allocations.filter { allocation in
      guard interval.contains(allocation.date) else { return false }
      return Self.bucket(envelopeID: allocation.sourceEnvelopeID, cardID: allocation.sourceCardID) == subject
        || Self.bucket(envelopeID: allocation.targetEnvelopeID, cardID: allocation.targetCardID) == subject
    }.count
  }

  private static func bucket(envelopeID: UUID?, cardID: UUID?) -> BudgetBucket {
    if let envelopeID { return .envelope(envelopeID) }
    if let cardID { return .cardPayment(cardID) }
    return .readyToAssign
  }

  private static func name(of bucket: BudgetBucket, envelopes: [BudgetEnvelope], accounts: [BudgetAccount]) -> String {
    switch bucket {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): envelopes.first { $0.id == id }?.name ?? "Deleted envelope"
    case .cardPayment(let id): (accounts.first { $0.id == id }?.name ?? "Card") + " payment"
    }
  }
}

struct MoneyMoveEntry: Identifiable, Equatable {
  var id: UUID
  var date: Date
  var createdAt: Date
  /// Money came into the bucket being viewed.
  var isIn: Bool
  /// Where the money came from, or where it went.
  var counterpart: String
  var amountMinor: Int64

  var title: String { isIn ? "From \(counterpart)" : "To \(counterpart)" }
  /// Positive coming in, negative going out.
  var signedMinor: Int64 { isIn ? amountMinor : -amountMinor }
}
