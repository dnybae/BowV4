import Foundation

struct TransactionFilter: Equatable {
  var accountID: UUID?
  var envelopeScope: TransactionEnvelopeScope = .all
  var needsApprovalOnly = false
  var startDate: Date?
  var endDate: Date?
  var minimumAmountMinor: Int64?
  var maximumAmountMinor: Int64?

  var activeCount: Int {
    [
      accountID != nil,
      envelopeScope != .all,
      needsApprovalOnly,
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

    if needsApprovalOnly && !item.needsApproval { return false }

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

enum TransactionEnvelopeScope: Hashable {
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
  var needsApproval: Bool = false
}
