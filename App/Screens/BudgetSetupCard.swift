import SwiftUI

/// A new budget's three first steps, at the top of Budget until all three are done.
struct BudgetSetupCard: View {
  var hasAccount: Bool
  var hasEnvelopes: Bool
  var hasAssigned: Bool
  var onAddAccount: () -> Void
  var onAddEnvelopes: () -> Void
  var onImportYNAB: () -> Void
  var onAssign: () -> Void

  private var currentStep: Int {
    if !hasAccount { return 0 }
    if !hasEnvelopes { return 1 }
    return 2
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Bow.Space.s4) {
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        Text("Set up your budget")
          .font(.bowTitle)
          .foregroundStyle(Bow.ink)
          .accessibilityAddTraits(.isHeader)
        Text("Three steps, and every dollar has a job.")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      step(0, title: "Add an account", detail: "Where your money lives: checking, savings, cash or a card.",
           isDone: hasAccount) {
        Button("Add Account", systemImage: "plus", action: onAddAccount)
          .bowPrimaryButton(size: .regular)
      }
      step(1, title: "Create envelopes", detail: "Bills, groceries, goals: a place for each job your money does.",
           isDone: hasEnvelopes) {
        HStack(spacing: Bow.Space.s2) {
          Button("Add Envelopes", systemImage: "plus", action: onAddEnvelopes)
            .bowPrimaryButton(size: .regular)
          Button("Import from YNAB", action: onImportYNAB)
            .bowSecondaryButton(size: .regular)
        }
      }
      step(2, title: "Assign your money", detail: "Move Ready to Assign into envelopes until it reaches zero.",
           isDone: hasAssigned) {
        Button("Assign Money", systemImage: "arrow.right", action: onAssign)
          .bowPrimaryButton(size: .regular)
      }
    }
    .padding(Bow.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .bowCard()
  }

  private func step<Action: View>(
    _ index: Int, title: String, detail: String, isDone: Bool,
    @ViewBuilder action: () -> Action
  ) -> some View {
    let isCurrent = index == currentStep && !isDone
    return HStack(alignment: .top, spacing: Bow.Space.s3) {
      ZStack {
        Circle()
          .fill(isDone ? AnyShapeStyle(Bow.funded) : AnyShapeStyle(isCurrent ? Bow.bowTint : Bow.well))
        if isDone {
          Image(systemName: "checkmark")
            .font(.bowFootnote.weight(.bold))
            .foregroundStyle(.white)
        } else {
          Text("\(index + 1)")
            .font(.bowFootnote.weight(.bold))
            .foregroundStyle(isCurrent ? Bow.bowInk : Bow.inkSoft)
        }
      }
      .frame(width: 28, height: 28)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Bow.Space.s2) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.bowHeadline)
            .foregroundStyle(isDone ? Bow.inkSoft : Bow.ink)
            .strikethrough(isDone)
          if isCurrent {
            Text(detail)
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1), \(title)")
        .accessibilityValue(isDone ? "Done" : isCurrent ? "Next" : "")
        if isCurrent {
          action()
        }
      }
      Spacer(minLength: 0)
    }
  }
}
