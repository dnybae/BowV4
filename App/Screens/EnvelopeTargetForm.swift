import SwiftUI

/// The one target editor: a hero amount, monthly or by a date, and a single line on what it means.
/// Shown as the Target sheet and pushed from the new and edit envelope sheets.
struct EnvelopeTargetForm: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var amountMinor: Int64
  @Binding var kind: TargetPlanKind
  @Binding var targetDate: Date
  var currencyCode: String
  /// What scheduled bills add to this month's target.
  var scheduledMinor: Int64 = 0
  /// Already saved at the start of this month, which a goal counts toward.
  var carriedInMinor: Int64 = 0
  /// Average monthly spending, offered as a starting amount.
  var suggestedMinor: Int64?
  var focusOnAppear = false
  var onRemove: (() -> Void)?
  /// Pushed from an envelope sheet, removing goes back to it.
  var dismissesOnRemove = false

  private var monthlyShareMinor: Int64? {
    guard kind == .byDate, amountMinor > 0 else { return nil }
    return EnvelopeTargetPlanner().monthlyMinor(
      targetMinor: amountMinor, targetDate: targetDate, scheduledMinor: 0,
      carriedInMinor: carriedInMinor, month: Date()
    ) ?? 0
  }

  private var showsSuggestion: Bool {
    kind == .monthly && suggestedMinor.map { $0 != amountMinor } == true
  }

  var body: some View {
    Form {
      Section {
        VStack(spacing: Bow.Space.s4) {
          CurrencyAmountField(kind == .byDate ? "Goal amount" : "Each month", minor: $amountMinor,
                              currencyCode: currencyCode, style: .editorHero, focusOnAppear: focusOnAppear)
          Picker("Target type", selection: $kind.animation()) {
            Text("Monthly").tag(TargetPlanKind.monthly)
            Text("By a date").tag(TargetPlanKind.byDate)
          }
          .pickerStyle(.segmented)
          summary
          if let suggestedMinor, showsSuggestion {
            Button {
              amountMinor = suggestedMinor
            } label: {
              Text("Suggested: \(BudgetMoney.formatted(suggestedMinor, currencyCode: currencyCode))")
                .monospacedDigit()
            }
            .bowSecondaryButton(size: .regular)
            .accessibilityHint("Your average monthly spending")
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Bow.Space.s2)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 0, leading: Bow.Space.s4, bottom: 0, trailing: Bow.Space.s4))

      if kind == .byDate {
        Section {
          NavigationLink {
            BowDatePickerScreen(title: "Goal date", date: $targetDate, range: Date()...Date.distantFuture)
          } label: {
            LabeledContent("Goal date", value: targetDate.formatted(.dateTime.month(.wide).year()))
          }
        }
        .listRowBackground(Bow.card)
      }

      if let onRemove {
        BowDestructiveSection("Remove target") {
          onRemove()
          if dismissesOnRemove { dismiss() }
        }
      }
    }
  }

  /// One quiet line under the controls: the monthly share of a goal, and any scheduled bills.
  @ViewBuilder
  private var summary: some View {
    let lines = [planLine, billsLine].compactMap { $0 }
    if !lines.isEmpty {
      Text(lines.joined(separator: " "))
        .font(.bowFootnote)
        .monospacedDigit()
        .foregroundStyle(Bow.inkSoft)
        .multilineTextAlignment(.center)
        .contentTransition(.numericText())
    }
  }

  private var planLine: String? {
    guard let monthlyShareMinor else { return nil }
    let until = targetDate.formatted(.dateTime.month(.wide).year())
    return "About \(BudgetMoney.formatted(monthlyShareMinor, currencyCode: currencyCode)) a month until \(until)."
  }

  private var billsLine: String? {
    guard scheduledMinor > 0 else { return nil }
    return "Scheduled bills add \(BudgetMoney.formatted(scheduledMinor, currencyCode: currencyCode)) this month."
  }
}
