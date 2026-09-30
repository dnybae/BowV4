import SwiftUI

/// A budget envelope row: status ring, name, what happened this month and a status pill.
struct EnvelopeBudgetRow: View {
  var name: String
  var availableMinor: Int64
  var cashOverspentMinor: Int64
  var creditOverspentMinor: Int64
  var assignedMinor: Int64
  var activityMinor: Int64
  var monthlyTargetMinor: Int64?
  var currencyCode: String

  private var status: EnvelopeStatus {
    EnvelopeStatus(
      availableMinor: availableMinor, assignedMinor: assignedMinor, activityMinor: activityMinor,
      monthlyTargetMinor: monthlyTargetMinor, currencyCode: currencyCode
    )
  }

  private var detail: String {
    if availableMinor < 0 {
      return cashOverspentMinor > 0 ? "Cash overspent"
        : creditOverspentMinor > 0 ? "Credit overspent · adds debt" : "Overspent"
    }
    let spent = BudgetMoney.formatted(max(0, -activityMinor), currencyCode: currencyCode)
    return "Spent \(spent) of \(BudgetMoney.formatted(assignedMinor, currencyCode: currencyCode))"
  }

  var body: some View {
    let status = status
    HStack(spacing: Bow.Space.s3) {
      StatusRing(fraction: status.ringFraction, state: status.state)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.bowBody)
          .foregroundStyle(Bow.ink)
        Text(detail)
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: Bow.Space.s2)
      StatusPill(text: status.pillText, state: status.state)
    }
    .frame(minHeight: 44)
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .combine)
  }
}
