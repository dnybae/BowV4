import SwiftUI

/// The first load of a tab (Budget, Accounts): the screen's own shapes, redacted and shimmering,
/// instead of a spinner. A totals strip, then a grouped list of rows.
struct BowOverviewSkeleton: View {
  /// Read by VoiceOver, e.g. "Calculating your budget".
  var accessibilityTitle: String

  private static let names = ["Groceries", "Rent", "Transport", "Dining out"]

  var body: some View {
    List {
      Section {
        BowStatStrip(stats: [
          .money("Assigned", 120_000), .money("Spent", 48_000), .money("Available", 72_000)
        ], currencyCode: "USD")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      Section {
        ForEach(Self.names, id: \.self) { name in
          HStack(spacing: Bow.Space.s3) {
            Circle()
              .stroke(Bow.well, lineWidth: 3)
              .frame(width: 28, height: 28)
            Text(name)
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            Spacer(minLength: Bow.Space.s2)
            Text("$000.00")
              .font(.bowAmountSm)
          }
          .frame(minHeight: 44)
        }
      }
      .listRowBackground(Bow.card)
    }
    .redacted(reason: .placeholder)
    .bowShimmer()
    .scrollDisabled(true)
    .bowListBackground { Bow.mist }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
  }
}
