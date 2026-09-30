import SwiftUI
import Charts

struct PayeeActivitySection: View {
  var activity: PayeeActivity
  var usualAccountName: String?
  var currencyCode: String

  private var hasRecentMonths: Bool {
    activity.months.contains { $0.totalMinor > 0 }
  }

  var body: some View {
    Section {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: Bow.Space.s3) { stats }
        VStack(alignment: .leading, spacing: Bow.Space.s3) { stats }
      }
      .padding(.vertical, Bow.Space.s1)

      if hasRecentMonths {
        Chart(activity.months) { month in
          BarMark(
            x: .value("Month", month.start, unit: .month),
            y: .value("Amount", Double(month.totalMinor) / 100)
          )
          .foregroundStyle(Bow.bow.gradient)
          .clipShape(Capsule())
        }
        .chartYAxis(.hidden)
        .chartXAxis {
          AxisMarks(values: .stride(by: .month)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
          }
        }
        .frame(height: 96)
        .padding(.vertical, Bow.Space.s1)
        .accessibilityLabel("Last 6 months")
      }

      if let usualAccountName {
        Label("Usually paid with \(usualAccountName)", systemImage: "creditcard")
          .font(.subheadline)
          .foregroundStyle(Bow.inkSoft)
      }
    } header: {
      Text("Activity")
    }
    .listRowBackground(Bow.card)
  }

  @ViewBuilder
  private var stats: some View {
    stat(activity.yearToDateTitle,
         value: BudgetMoney.formatted(activity.yearToDateMinor, currencyCode: currencyCode))
    stat("Average",
         value: BudgetMoney.formatted(activity.averageMinor, currencyCode: currencyCode))
    if let frequency = activity.frequencyDescription {
      stat("How often", value: frequency)
    } else {
      stat("Payments", value: activity.transactionCount.formatted())
    }
  }

  private func stat(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(Bow.inkSoft)
      Text(value)
        .font(.headline)
        .fontDesign(.rounded)
        .monospacedDigit()
        .foregroundStyle(Bow.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
