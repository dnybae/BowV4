import SwiftUI

/// Placeholder transaction rows while a list loads: the real row, redacted, with a gentle shimmer.
/// A `ForEach`, so each placeholder is its own row inside a List section.
struct BowTransactionSkeletonRows: View {
  var count = 4

  var body: some View {
    ForEach(0..<count, id: \.self) { index in
      TransactionRowView(model: .placeholder(index), currencyCode: "USD")
        .redacted(reason: .placeholder)
        .bowShimmer()
        .accessibilityHidden(true)
    }
  }
}

/// A status line for work in progress ("Syncing with your bank…"), shimmering instead of spinning.
struct BowLoadingLabel: View {
  var title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.bowSubhead.weight(.medium))
      .foregroundStyle(Bow.inkSoft)
      .bowShimmer()
      .accessibilityAddTraits(.updatesFrequently)
  }
}

extension TransactionRowModel {
  /// A believable row for skeletons. Varies a little by index so the column doesn't look stamped.
  static func placeholder(_ index: Int = 0) -> TransactionRowModel {
    let titles = ["Corner Market", "Transit Pass", "Coffee Shop", "Electric Company"]
    return TransactionRowModel(
      id: "placeholder-\(index)",
      title: titles[index % titles.count],
      logoName: "",
      merchantDomain: nil,
      kind: .expense,
      accountName: "Everyday Checking",
      envelopeName: "Groceries",
      amountMinor: -[4_250, 275, 1_830, 9_600][index % 4],
      state: .normal
    )
  }
}

extension View {
  /// A soft highlight that sweeps across loading content. Off with Reduce Motion.
  func bowShimmer() -> some View {
    modifier(BowShimmer())
  }
}

private struct BowShimmer: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var scheme
  @State private var phase: CGFloat = -1

  func body(content: Content) -> some View {
    content
      .overlay {
        if !reduceMotion {
          GeometryReader { geometry in
            LinearGradient(
              colors: [.clear, .white.opacity(scheme == .dark ? 0.14 : 0.6), .clear],
              startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: phase * geometry.size.width)
          }
          .mask(content)
          .allowsHitTesting(false)
        }
      }
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
      }
  }
}
