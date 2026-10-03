import SwiftUI
import SwiftData

/// A card's payoff goal, like YNAB's: a set amount each month, or a payoff date from which
/// Bow works out the monthly amount.
struct CardDebtGoalEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var card: BudgetAccount
  /// Owed today; where a new goal's progress starts.
  var currentDebtMinor: Int64
  /// The debt the goal spreads out (see CardPaymentDetailScreen.payoffDebt).
  var payoffDebtMinor: Int64
  var month: Date
  var currencyCode: String
  @State private var kind: TargetPlanKind
  @State private var monthlyMinor: Int64
  @State private var targetDate: Date
  @State private var resetBaseline = false
  @State private var message: String?

  private let planner = CardPayoffPlanner()

  init(card: BudgetAccount, currentDebtMinor: Int64, payoffDebtMinor: Int64, month: Date, currencyCode: String) {
    self.card = card
    self.currentDebtMinor = currentDebtMinor
    self.payoffDebtMinor = payoffDebtMinor
    self.month = month
    self.currencyCode = currencyCode
    _kind = State(initialValue: card.debtGoalDate == nil ? .monthly : .byDate)
    _monthlyMinor = State(initialValue: card.debtMonthlyTargetMinor ?? 0)
    _targetDate = State(initialValue: card.debtGoalDate
      ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
  }

  private var hasGoal: Bool { card.debtMonthlyTargetMinor != nil || card.debtGoalDate != nil }

  /// The amount by the payoff date, worked out the same way as on the card's screen.
  private var calculatedMinor: Int64 {
    planner.monthlyMinor(debtMinor: payoffDebtMinor, monthlyTargetMinor: nil, goalDate: targetDate, month: month) ?? 0
  }

  private var summary: String? {
    switch kind {
    case .byDate:
      return payoffDebtMinor > 0
        ? "Bow spreads this card’s debt evenly until \(targetDate.formatted(.dateTime.month(.wide).year())). The amount adjusts each month as you pay."
        : "No debt left to spread out."
    case .monthly:
      guard let payoff = planner.payoffMonth(debtMinor: payoffDebtMinor, monthlyMinor: monthlyMinor, from: month)
      else { return nil }
      return "Paid off around \(payoff.formatted(.dateTime.month(.wide).year()))."
    }
  }

  private var hasChanges: Bool {
    switch kind {
    case .monthly:
      return card.debtGoalDate != nil || monthlyMinor != (card.debtMonthlyTargetMinor ?? 0) || resetBaseline
    case .byDate:
      return card.debtGoalDate != targetDate || card.debtMonthlyTargetMinor != nil || resetBaseline
    }
  }

  private var canSave: Bool { hasChanges && (kind == .byDate || monthlyMinor > 0) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: Bow.Space.s4) {
            switch kind {
            case .monthly:
              CurrencyAmountField("Each month", minor: $monthlyMinor, currencyCode: currencyCode,
                                  style: .editorHero, focusOnAppear: !hasGoal)
            case .byDate:
              // Worked out from the date, so it reads like the amount field but isn't typed.
              VStack(spacing: Bow.Space.s1) {
                Text("Each month")
                  .font(.bowSubhead)
                  .foregroundStyle(Bow.inkSoft)
                MoneyText(minor: calculatedMinor, currencyCode: currencyCode)
                  .font(.system(size: 50, weight: .semibold, design: .rounded))
                  .foregroundStyle(Bow.ink)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
              }
              .accessibilityElement(children: .combine)
            }
            Picker("Goal type", selection: $kind.animation()) {
              Text("Monthly amount").tag(TargetPlanKind.monthly)
              Text("Pay off by date").tag(TargetPlanKind.byDate)
            }
            .pickerStyle(.segmented)
            if let summary {
              Text(summary)
                .font(.bowFootnote)
                .monospacedDigit()
                .foregroundStyle(Bow.inkSoft)
                .multilineTextAlignment(.center)
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
              BowDatePickerScreen(title: "Pay off by", date: $targetDate, range: Date()...Date.distantFuture)
            } label: {
              LabeledContent("Pay off by", value: targetDate.formatted(.dateTime.month(.wide).year()))
            }
          }
          .listRowBackground(Bow.card)
        }

        if card.debtGoalStartMinor != nil && hasGoal {
          Section {
            Toggle("Restart progress from today", isOn: $resetBaseline)
          } footer: {
            Text("Progress then counts from today’s \(BudgetMoney.formatted(currentDebtMinor, currencyCode: currencyCode)) owed.")
              .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        }

        if hasGoal {
          BowDestructiveSection("Remove payoff goal") { removeGoal() }
        }
      }
      .bowSkyList(mood: .dawn, height: 420)
      .bowEditorSheet(hasChanges: hasChanges)
      .navigationTitle("Payoff goal")
      .navigationSubtitle(card.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
      }
      // A money sheet: one primary action at the bottom, like the other money editors.
      .safeAreaInset(edge: .bottom) {
        BowBottomAction("Save goal", isEnabled: canSave) { save() }
      }
      .bowErrorAlert("Couldn’t save goal", message: $message)
    }
  }

  private func save() {
    switch kind {
    case .monthly:
      card.debtMonthlyTargetMinor = monthlyMinor > 0 ? monthlyMinor : nil
      card.debtGoalDate = nil
    case .byDate:
      // Bow works the amount out each month from the date.
      card.debtMonthlyTargetMinor = nil
      card.debtGoalDate = targetDate
    }
    if card.debtGoalStartMinor == nil || resetBaseline {
      card.debtGoalStartMinor = currentDebtMinor
    }
    commit()
  }

  private func removeGoal() {
    card.debtMonthlyTargetMinor = nil
    card.debtGoalDate = nil
    card.debtGoalStartMinor = nil
    commit()
  }

  private func commit() {
    do {
      try modelContext.save()
      dismiss()
    } catch { message = error.localizedDescription }
  }
}
