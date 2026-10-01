import SwiftUI

/// The first load of a tab (Budget, Accounts): the screen's own shapes, redacted and shimmering,
/// instead of a spinner. A totals strip, then a few cards.
struct BowOverviewSkeleton: View {
  var mood: SkyMood = .dawn
  /// Read by VoiceOver, e.g. "Calculating your budget".
  var accessibilityTitle: String

  private static let names = ["Groceries", "Rent", "Transport", "Dining out"]

  var body: some View {
    ScrollView {
      VStack(spacing: Bow.Space.s2) {
        BowStatStrip(stats: [
          .money("Assigned", 120_000), .money("Spent", 48_000), .money("Available", 72_000)
        ], currencyCode: "USD")
        .padding(.bottom, Bow.Space.s4)

        ForEach(Self.names, id: \.self) { name in
          BowItemCard {
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
          }
        }
      }
      .redacted(reason: .placeholder)
      .bowShimmer()
      .padding(.horizontal, Bow.Space.s4)
      .padding(.top, Bow.Space.s2)
    }
    .scrollDisabled(true)
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: mood) }
        .ignoresSafeArea()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
  }
}
