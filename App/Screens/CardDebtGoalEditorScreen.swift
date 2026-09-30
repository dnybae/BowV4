import SwiftUI
import SwiftData

struct CardDebtGoalEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var card: BudgetAccount
  var currentDebtMinor: Int64
  var currencyCode: String
  @State private var monthlyMinor: Int64
  @State private var hasDate: Bool
  @State private var targetDate: Date
  @State private var resetBaseline = false
  @State private var message: String?

  init(card: BudgetAccount, currentDebtMinor: Int64, currencyCode: String) {
    self.card = card
    self.currentDebtMinor = currentDebtMinor
    self.currencyCode = currencyCode
    _monthlyMinor = State(initialValue: card.debtMonthlyTargetMinor ?? 0)
    _hasDate = State(initialValue: card.debtGoalDate != nil)
    _targetDate = State(initialValue: card.debtGoalDate ?? Date())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Debt today") {
            Text(BudgetMoney.formatted(currentDebtMinor, currencyCode: currencyCode))
              .fontDesign(.rounded).monospacedDigit()
          }
          CurrencyAmountField("Monthly funding target", minor: $monthlyMinor, currencyCode: currencyCode)
          Toggle("Set payoff date", isOn: $hasDate)
          if hasDate {
            DatePicker("Pay off by", selection: $targetDate, in: Date()..., displayedComponents: .date)
          }
        } footer: {
          Text("A target guides your plan. It does not move money into the card payment envelope.")
        }
        .listRowBackground(Bow.card)
        if card.debtGoalStartMinor != nil {
          Section {
            Button("Start a new payoff goal", systemImage: "arrow.counterclockwise") {
              resetBaseline = true
            }
          } footer: {
            Text(resetBaseline
              ? "Saving will restart progress from today’s debt balance."
              : "Restarts progress from today’s debt balance when you save.")
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle("Payoff goal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
      }
      .alert("Couldn’t save goal", isPresented: Binding(
        get: { message != nil }, set: { if !$0 { message = nil } }
      )) {
        Button("OK") { message = nil }
      } message: {
        Text(message ?? "")
      }
    }
  }

  private func save() {
    card.debtMonthlyTargetMinor = monthlyMinor > 0 ? monthlyMinor : nil
    card.debtGoalDate = hasDate ? targetDate : nil
    if card.debtGoalStartMinor == nil || resetBaseline {
      card.debtGoalStartMinor = currentDebtMinor
    }
    do {
      try modelContext.save()
      dismiss()
    } catch { message = error.localizedDescription }
  }
}
