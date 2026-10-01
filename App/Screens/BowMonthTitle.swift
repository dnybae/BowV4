import SwiftUI

/// Month and year in the navigation bar, on Budget and Calendar. The month slides in from the direction the user moved.
struct BowMonthTitle: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var month: Date
  var direction: Edge
  var isLoading = false

  var body: some View {
    HStack(spacing: Bow.Space.s2) {
      VStack(spacing: 0) {
        Text(month.formatted(.dateTime.month(.wide)))
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
        Text(month.formatted(.dateTime.year()))
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      .id(month)
      .transition(reduceMotion ? .opacity : .push(from: direction))
      if isLoading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Loading month")
      }
    }
    .clipped()
    .bowAnimation(value: month)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
