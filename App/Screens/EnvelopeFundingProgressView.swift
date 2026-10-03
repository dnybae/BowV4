import SwiftUI

/// A labelled target bar, independent of the envelope's remaining spendable money.
struct EnvelopeFundingProgressView: View {
  var progress: EnvelopeFundingProgress
  var currencyCode: String

  private var fundedText: String {
    let assigned = BudgetMoney.formatted(progress.assignedMinor, currencyCode: currencyCode)
    let target = BudgetMoney.formatted(progress.targetMinor, currencyCode: currencyCode)
    return "\(assigned) of \(target) funded"
  }

  private var statusText: String {
    progress.isFullyFunded ? "Target met"
      : "Needs \(BudgetMoney.formatted(progress.remainingMinor, currencyCode: currencyCode))"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Bow.Space.s3) {
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        Text("Target funding")
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
        Text(fundedText)
          .font(.bowSubhead)
          .monospacedDigit()
          .foregroundStyle(Bow.inkSoft)
      }

      SwiftUI.ProgressView(value: progress.fraction)
        .tint(progress.isFullyFunded ? Bow.funded : Bow.needs)
        .bowAnimation(value: progress.fraction)

      Label(statusText, systemImage: progress.isFullyFunded ? "checkmark" : "minus")
        .font(.bowSubhead)
        .monospacedDigit()
        .foregroundStyle(progress.isFullyFunded ? Bow.fundedInk : Bow.needsInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Bow.Space.s4)
    .background(Bow.card, in: RoundedRectangle(cornerRadius: Bow.Radius.lg))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Target funding")
    .accessibilityValue("\(fundedText), \(statusText)")
  }
}
