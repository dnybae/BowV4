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
          BowContextCard(name: card.name, systemImage: "creditcard", context: "Debt today") {
            MoneyText(minor: currentDebtMinor, currencyCode: currencyCode)
              .font(.bowTitle)
              .foregroundStyle(Bow.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
          CurrencyAmountField("Fund each month", minor: $monthlyMinor, currencyCode: currencyCode,
                              systemImage: "calendar.badge.clock")
          Toggle(isOn: $hasDate) {
            Label("Set a payoff date", systemImage: "flag").labelStyle(.bowTile)
          }
          if hasDate {
            NavigationLink {
              BowDatePickerScreen(title: "Pay off by", date: $targetDate, range: Date()...Date.distantFuture)
            } label: {
              BowTileValueRow("Pay off by", systemImage: "calendar",
                              value: targetDate.formatted(date: .abbreviated, time: .omitted))
            }
          }
        } footer: {
          Text("A target guides your plan. It does not move money into the card payment envelope.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
        if card.debtGoalStartMinor != nil {
          Section {
            Button("Start a new payoff goal", systemImage: "arrow.counterclockwise") {
              resetBaseline = true
            }
          } footer: {
            Group {
              Text(resetBaseline
                ? "Saving will restart progress from today’s debt balance."
                : "Restarts progress from today’s debt balance when you save.")
            }
            .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowSkyList(mood: .dawn, height: 420)
      .bowAnimation(value: hasDate)
      .bowEditorSheet(hasChanges: hasChanges)
      .navigationTitle("Payoff goal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
      }
      .bowErrorAlert("Couldn’t save goal", message: $message)
    }
  }

  private var hasChanges: Bool {
    monthlyMinor != (card.debtMonthlyTargetMinor ?? 0) || hasDate != (card.debtGoalDate != nil)
      || (hasDate && targetDate != card.debtGoalDate) || resetBaseline
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
