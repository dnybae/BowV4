import Foundation

/// A contextual banner at the top of the Budget screen, like a notification: it only appears
/// when there's something to act on, and tapping it starts that action.
struct BudgetNotice: Identifiable, Equatable {
  var kind: Kind
  /// Shown before the title as a rolling money amount.
  var amountMinor: Int64
  var title: String
  var message: String
  /// Past months are view only, and some states have nothing to move.
  var isActionable: Bool
  var accessibilityHint: String

  var id: Kind { kind }

  enum Kind: Hashable {
    /// Ready to Assign is negative: more was assigned than there is cash.
    case deficit
    /// One or more envelopes spent more than they had.
    case overspent
    /// Money is waiting in Ready to Assign.
    case readyToAssign
  }

  enum Tone { case brand, caution, critical }

  var tone: Tone {
    switch kind {
    case .deficit: .critical
    case .overspent: .caution
    case .readyToAssign: .brand
    }
  }

  var symbol: String {
    switch kind {
    case .deficit: "minus.circle.fill"
    case .overspent: "exclamationmark.triangle.fill"
    case .readyToAssign: "tray.full.fill"
    }
  }

  /// The notices for a month, most urgent first. A deficit and Ready to Assign never appear together.
  static func notices(
    readyToAssignMinor: Int64,
    overspending: OverspendingSummary,
    isPastMonth: Bool,
    canMoveToReadyToAssign: Bool,
    hasEnvelopes: Bool
  ) -> [BudgetNotice] {
    var notices: [BudgetNotice] = []

    if readyToAssignMinor < 0 {
      notices.append(BudgetNotice(
        kind: .deficit,
        amountMinor: -readyToAssignMinor,
        title: "over budget",
        message: isPastMonth
          ? "More was assigned than you had when this month ended."
          : canMoveToReadyToAssign
            ? "You assigned more than you have. Move money back from envelopes to cover it."
            : "You assigned more than you have. Add income to cover it.",
        isActionable: !isPastMonth && canMoveToReadyToAssign,
        accessibilityHint: "Opens Move Money to cover the deficit"
      ))
    }

    if !overspending.isEmpty {
      let count = overspending.items.count
      let envelopes = count == 1 ? "1 envelope" : "\(count) envelopes"
      let message: String
      if isPastMonth {
        message = "In \(envelopes), left uncovered when this month ended."
      } else {
        switch (overspending.cashMinor > 0, overspending.creditMinor > 0) {
        case (true, true): message = "In \(envelopes). Cover it to keep next month and your card payments on track."
        case (false, true): message = "In \(envelopes), on credit cards. Cover it so your card payments stay funded."
        default: message = "In \(envelopes). Cover it now or it comes out of next month’s Ready to Assign."
        }
      }
      notices.append(BudgetNotice(
        kind: .overspent,
        amountMinor: overspending.totalMinor,
        title: "overspent",
        message: message,
        isActionable: !isPastMonth,
        accessibilityHint: "Choose envelopes to cover the overspending"
      ))
    }

    if readyToAssignMinor > 0 {
      notices.append(BudgetNotice(
        kind: .readyToAssign,
        amountMinor: readyToAssignMinor,
        title: "Ready to Assign",
        message: isPastMonth
          ? "Left unassigned when this month ended."
          : hasEnvelopes ? "Give every dollar a job." : "Add an envelope to start assigning.",
        isActionable: !isPastMonth,
        accessibilityHint: hasEnvelopes ? "Shows envelopes and their remaining targets" : "Adds an envelope"
      ))
    }

    return notices
  }
}
