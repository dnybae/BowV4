import SwiftUI

struct ScheduledTargetRow: View {
  var contribution: ScheduleTargetContribution
  var currencyCode: String

  private var detail: String {
    let amount = BudgetMoney.formatted(contribution.amountMinor, currencyCode: currencyCode)
    return contribution.occurrences == 1
      ? "Scheduled · due once this month"
      : "Scheduled · \(contribution.occurrences) × \(amount) this month"
  }

  var body: some View {
    LabeledContent {
      Text(BudgetMoney.formatted(contribution.totalMinor, currencyCode: currencyCode))
    } label: {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(contribution.payee)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "calendar.badge.clock")
          .foregroundStyle(.tint)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
