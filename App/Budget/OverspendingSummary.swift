import Foundation

/// Every overspent budget envelope in a month, in budget order, split into cash and credit overspending.
/// Covering an envelope pays back its cash overspending first, then moves the rest into the card payments it's owed to.
struct OverspendingSummary {
  var items: [Item]

  struct Item: Identifiable, Hashable {
    var envelopeID: UUID
    /// Everything needed to bring the envelope back to zero.
    var totalMinor: Int64
    var cashMinor: Int64
    /// Credit overspending by card ID.
    var creditByCard: [UUID: Int64]

    var id: UUID { envelopeID }
    var creditMinor: Int64 { creditByCard.values.reduce(0, +) }
  }

  /// - Parameter cardID: When set, only envelopes overspent on that card are included.
  init(snapshot: BudgetSnapshot, envelopes: [BudgetEnvelope], groups: [BudgetGroup], cardID: UUID? = nil) {
    let groupOrder = Dictionary(groups.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
    var creditByEnvelope: [UUID: [UUID: Int64]] = [:]
    for (key, amount) in snapshot.creditShortfallByCard where amount > 0 {
      creditByEnvelope[key.envelopeID, default: [:]][key.cardID, default: 0] += amount
    }
    items = envelopes
      .filter { $0.paymentAccountID == nil && snapshot.available(for: $0.id) < 0 }
      .sorted {
        let lhs = (groupOrder[$0.groupID] ?? .max, $0.sortOrder)
        let rhs = (groupOrder[$1.groupID] ?? .max, $1.sortOrder)
        return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
      }
      .map { envelope in
        let total = -snapshot.available(for: envelope.id)
        let credit = creditByEnvelope[envelope.id] ?? [:]
        let cash = min(total, max(0, snapshot.cashShortfall[envelope.id, default: 0]))
        return Item(envelopeID: envelope.id, totalMinor: total, cashMinor: cash, creditByCard: credit)
      }
      .filter { item in cardID.map { item.creditByCard[$0, default: 0] > 0 } ?? true }
  }

  var totalMinor: Int64 { items.reduce(0) { $0 + $1.totalMinor } }
  var cashMinor: Int64 { items.reduce(0) { $0 + $1.cashMinor } }
  var creditMinor: Int64 { items.reduce(0) { $0 + $1.creditMinor } }
  var isEmpty: Bool { items.isEmpty }

  /// Credit overspending charged to one card.
  func creditMinor(onCard cardID: UUID) -> Int64 {
    items.reduce(0) { $0 + $1.creditByCard[cardID, default: 0] }
  }
}
