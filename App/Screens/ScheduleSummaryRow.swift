import SwiftUI

/// A recurring transaction in a detail screen's list: payee over how often, amount trailing.
struct ScheduleSummaryRow: View {
  var schedule: BudgetSchedule
  var currencyCode: String

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(schedule.payee.isEmpty ? "Scheduled bill" : schedule.payee)
          .foregroundStyle(Bow.ink)
        Text(schedule.frequency.title)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: Bow.Space.s2)
      MoneyText(minor: schedule.amountMinor, currencyCode: currencyCode)
        .foregroundStyle(Bow.inkSoft)
    }
    .accessibilityElement(children: .combine)
  }
}
