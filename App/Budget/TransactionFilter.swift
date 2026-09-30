import Foundation

struct TransactionFilter: Hashable, Sendable {
  var accountID: UUID?
  var envelopeScope: TransactionEnvelopeScope = .all
  var status: TransactionStatusScope = .all
  var startDate: Date?
  var endDate: Date?
  var minimumAmountMinor: Int64?
  var maximumAmountMinor: Int64?

  var activeCount: Int {
    [
      accountID != nil,
      envelopeScope != .all,
      status != .all,
      startDate != nil,
      endDate != nil,
      minimumAmountMinor != nil,
      maximumAmountMinor != nil
    ].filter { $0 }.count
  }

  var isActive: Bool { activeCount > 0 }

  func includes(_ item: TransactionFilterItem, calendar: Calendar = .current) -> Bool {
    if let accountID,
       item.accountID != accountID && item.transferAccountID != accountID {
      return false
    }

    switch envelopeScope {
    case .all:
      break
    case .uncategorized:
      guard item.isUncategorizedExpense else { return false }
    case .envelope(let id):
      guard item.envelopeID == id else { return false }
    }

    if status == .needsAttention && !item.needsAttention { return false }
    if status == .matched && !item.isMatched { return false }

    if let startDate,
       calendar.compare(item.date, to: startDate, toGranularity: .day) == .orderedAscending {
      return false
    }
    if let endDate,
       calendar.compare(item.date, to: endDate, toGranularity: .day) == .orderedDescending {
      return false
    }

    let amount = item.amountMinor.magnitude
    if let minimumAmountMinor, amount < UInt64(max(0, minimumAmountMinor)) { return false }
    if let maximumAmountMinor, amount > UInt64(max(0, maximumAmountMinor)) { return false }
    return true
  }
}

enum TransactionStatusScope: String, Hashable, Sendable, CaseIterable {
  case all
  case needsAttention
  case matched

  var title: String {
    switch self {
    case .all: "All"
    case .needsAttention: "Needs attention"
    case .matched: "Matched"
    }
  }
}

enum TransactionEnvelopeScope: Hashable, Sendable {
  case all
  case uncategorized
  case envelope(UUID)
}

struct TransactionFilterItem {
  var accountID: UUID
  var transferAccountID: UUID?
  var envelopeID: UUID?
  var date: Date
  var amountMinor: Int64
  var isUncategorizedExpense: Bool
  var needsAttention: Bool = false
  var isMatched: Bool = false
}
