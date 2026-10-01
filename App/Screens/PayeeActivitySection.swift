import SwiftUI
import Charts

/// The last six months of a payee's activity as a bar chart. The totals sit in the stat strip above.
struct PayeeActivitySection: View {
  var activity: PayeeActivity

  private var hasRecentMonths: Bool {
    activity.months.contains { $0.totalMinor > 0 }
  }

  var body: some View {
    if hasRecentMonths {
      Section("Last 6 months") {
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
      .listRowBackground(Bow.card)
    }
  }
}

extension PayeeActivity {
  /// This year, Average and How often (or Payments), for the payee's stat strip.
  func stats(currencyCode: String) -> [BowStat] {
    [
      .money(yearToDateTitle, yearToDateMinor),
      .money("Average", averageMinor),
      frequencyDescription.map { .text("How often", $0) } ?? .text("Payments", transactionCount.formatted())
    ]
  }
}
