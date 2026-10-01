import SwiftUI

/// The line under an incoming item's name in Spending and Calendar: an 8pt dot and short text.
/// Pair it with `.listRowBackground(status.rowBackground)` so the row picks up its tint.
struct TransactionStatusLine: View {
  var status: TransactionRowStatus
  /// Overrides the default wording, e.g. "Scheduled, due today".
  var text: String? = nil
  @ScaledMetric(relativeTo: .subheadline) private var dotSize: CGFloat = 8

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(status.ink)
        .frame(width: dotSize, height: dotSize)
        .accessibilityHidden(true)
      Text(text ?? status.title)
        .font(.bowSubhead.weight(.semibold))
        .foregroundStyle(status.ink)
    }
  }
}

extension TransactionRowModel.State {
  /// The status line and row tint for this state; nil for a normal row.
  var rowStatus: TransactionRowStatus? {
    switch self {
    case .normal: nil
    case .attention: .needsReview
    case .scheduled: .scheduled
    case .pending: .pending
    }
  }

  /// The status line's wording.
  var label: String? {
    switch self {
    case .normal: nil
    case .attention(let label, _), .scheduled(let label), .pending(let label): label
    }
  }
}

enum TransactionRowStatus: Equatable {
  case needsReview, scheduled, pending

  var title: String {
    switch self {
    case .needsReview: "Needs review"
    case .scheduled: "Scheduled"
    case .pending: "Pending"
    }
  }

  var ink: Color {
    switch self {
    case .needsReview: Bow.needsInk
    case .scheduled: Bow.bowInk
    case .pending: Bow.inkSoft
    }
  }

  /// The row's background: tinted for review and due bills, the plain card for pending.
  var rowBackground: Color {
    switch self {
    case .needsReview: Bow.needsTint
    case .scheduled: Bow.bowTint
    case .pending: Bow.card
    }
  }
}
