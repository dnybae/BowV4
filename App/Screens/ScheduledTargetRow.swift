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
      MoneyText(minor: contribution.totalMinor, currencyCode: currencyCode)
    } label: {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(contribution.payee)
          Text(detail)
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
        }
      } icon: {
        Image(systemName: "calendar")
      }
      .labelStyle(.bowTile)
    }
    .accessibilityElement(children: .combine)
  }
}
