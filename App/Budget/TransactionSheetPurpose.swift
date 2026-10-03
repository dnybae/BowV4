import Foundation

/// What a transaction sheet is for. Every transaction, in every state, opens the same sheet with
/// the same fields in the same order; the purpose only changes the status under the amount and
/// the bottom button.
enum TransactionSheetPurpose: Equatable {
  case add
  case edit
  /// From the bank, or otherwise waiting for the user to look it over.
  case approve
  /// Pending at the bank and not in the budget yet.
  case enterPending
  /// A scheduled bill or deposit that's come due.
  case enterScheduled

  /// An existing transaction is approved while it still needs review; otherwise it's edited.
  init(existingNeedsReview: Bool) {
    self = existingNeedsReview ? .approve : .edit
  }

  /// The bank or the schedule sets the direction, so Type stays put but can't change.
  var locksType: Bool {
    switch self {
    case .add, .edit: false
    case .approve, .enterPending, .enterScheduled: true
    }
  }

  func primaryTitle(signedAmount: String, amountIsZero: Bool, isScheduling: Bool) -> String {
    switch self {
    case .add:
      if isScheduling { return "Schedule \(signedAmount)" }
      return amountIsZero ? "Add Transaction" : "Add \(signedAmount)"
    case .edit: return isScheduling ? "Schedule \(signedAmount)" : "Save"
    case .approve: return "Approve"
    case .enterPending, .enterScheduled: return "Enter Now"
    }
  }

  var primarySystemImage: String? {
    switch self {
    case .add, .edit: nil
    case .approve: "checkmark.circle.fill"
    case .enterPending, .enterScheduled: "arrow.down.circle.fill"
    }
  }
}

/// The short status under a transaction sheet's amount.
enum TransactionSheetStatus: Equatable {
  case needsReview
  case pendingAtBank
  case dueToday
  case overdue
  case due(Date)
  /// Confirmed by the bank: imported, matched, or ticked off while reconciling.
  case cleared
  /// Only in Bow so far. Without a bank connection, you clear it when you reconcile.
  case uncleared

  /// Nil while adding a transaction: there's no state to show yet.
  init?(
    purpose: TransactionSheetPurpose,
    isPendingAtBank: Bool = false,
    isCleared: Bool = false,
    dueDate: Date? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) {
    switch purpose {
    case .add:
      return nil
    case .approve:
      self = .needsReview
    case .enterPending:
      self = .pendingAtBank
    case .enterScheduled:
      guard let dueDate else { self = .dueToday; return }
      if calendar.isDate(dueDate, inSameDayAs: now) {
        self = .dueToday
      } else if dueDate < now {
        self = .overdue
      } else {
        self = .due(dueDate)
      }
    case .edit:
      if isPendingAtBank {
        self = .pendingAtBank
      } else if isCleared {
        self = .cleared
      } else {
        self = .uncleared
      }
    }
  }

  var text: String {
    switch self {
    case .needsReview: "Needs review"
    case .pendingAtBank: "Pending at bank"
    case .dueToday: "Due today"
    case .overdue: "Overdue"
    case .due(let date): "Due \(date.formatted(.dateTime.month(.abbreviated).day()))"
    case .cleared: "Cleared"
    case .uncleared: "Uncleared"
    }
  }
}
