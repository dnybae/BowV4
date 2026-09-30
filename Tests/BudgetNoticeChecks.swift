import Foundation

@main
struct BudgetNoticeChecks {
  static func main() {
    let none = OverspendingSummary(items: [])
    let overspent = OverspendingSummary(items: [
      .init(envelopeID: UUID(), totalMinor: 4_000, cashMinor: 4_000, creditByCard: [:]),
      .init(envelopeID: UUID(), totalMinor: 1_500, cashMinor: 0, creditByCard: [UUID(): 1_500])
    ])

    // Nothing to act on: no banners.
    let quiet = notices(readyToAssign: 0, overspending: none)
    precondition(quiet.isEmpty, "Zero Ready to Assign and no overspending shows nothing")

    // Money waiting: a single Ready to Assign banner with the amount.
    let ready = notices(readyToAssign: 124_000, overspending: none)
    precondition(ready.map(\.kind) == [.readyToAssign])
    precondition(ready[0].amountMinor == 124_000 && ready[0].isActionable)
    precondition(ready[0].tone == .brand)

    // A cent still counts: every dollar gets a job.
    precondition(notices(readyToAssign: 1, overspending: none).map(\.kind) == [.readyToAssign])

    // Deficit replaces Ready to Assign, shows a positive amount, and is the most urgent.
    let deficit = notices(readyToAssign: -12_000, overspending: overspent)
    precondition(deficit.map(\.kind) == [.deficit, .overspent], "Urgent banners come first")
    precondition(deficit[0].amountMinor == 12_000 && deficit[0].tone == .critical)
    precondition(deficit[1].amountMinor == 5_500 && deficit[1].tone == .caution)
    precondition(deficit[1].message.hasPrefix("In 2 envelopes"))

    // Overspending sits above money waiting to be assigned.
    let both = notices(readyToAssign: 3_000, overspending: overspent)
    precondition(both.map(\.kind) == [.overspent, .readyToAssign])

    // A deficit with nothing to move from can't open Move Money.
    let stuck = notices(readyToAssign: -500, overspending: none, canMove: false)
    precondition(!stuck[0].isActionable && stuck[0].message.contains("Add income"))

    // Past months keep their banners but are view only.
    let past = notices(readyToAssign: 3_000, overspending: overspent, isPastMonth: true)
    precondition(past.map(\.kind) == [.overspent, .readyToAssign])
    precondition(past.allSatisfy { !$0.isActionable })
    precondition(past[1].message == "Left unassigned when this month ended.")

    // No envelopes yet: the banner explains the next step.
    let empty = BudgetNotice.notices(
      readyToAssignMinor: 5_000, overspending: none, isPastMonth: false,
      canMoveToReadyToAssign: false, hasEnvelopes: false
    )
    precondition(empty[0].message == "Add an envelope to start assigning.")

    print("Budget notice checks passed")
  }

  private static func notices(
    readyToAssign: Int64, overspending: OverspendingSummary,
    isPastMonth: Bool = false, canMove: Bool = true
  ) -> [BudgetNotice] {
    BudgetNotice.notices(
      readyToAssignMinor: readyToAssign, overspending: overspending, isPastMonth: isPastMonth,
      canMoveToReadyToAssign: canMove, hasEnvelopes: true
    )
  }
}
