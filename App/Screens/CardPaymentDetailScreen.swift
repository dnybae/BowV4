import SwiftUI

struct CardPaymentDetailScreen: View {
  var card: BudgetAccount
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var transactions: [BudgetTransaction]
  var schedules: [BudgetSchedule]
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var showingGoalEditor = false
  @State private var showingAccountEditor = false

  private var owed: Int64 { max(0, -snapshot.accountBalances[card.id, default: 0]) }
  private var reserved: Int64 { max(0, snapshot.paymentAvailable[card.id, default: 0]) }
  private var baseline: Int64 { max(owed, card.debtGoalStartMinor ?? 0) }
  private var debtProgress: Double {
    guard baseline > 0 else { return 1 }
    return min(1, max(0, Double(baseline - owed) / Double(baseline)))
  }
  private var cardTransactions: [BudgetTransaction] {
    transactions.filter { $0.accountID == card.id || $0.transferAccountID == card.id }
      .sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
  }
  private var cardSchedules: [BudgetSchedule] {
    schedules.filter { $0.accountID == card.id }.sorted { $0.payee < $1.payee }
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text("Payment Available").font(.subheadline).foregroundStyle(.secondary)
          Text(BudgetMoney.formatted(reserved, currencyCode: currencyCode))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
          Text(snapshot.month.formatted(.dateTime.month(.wide).year()))
            .font(.footnote).foregroundStyle(.secondary)
          Text(owed > reserved
            ? "\(BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)) of current debt needs funding."
            : "Current debt is covered by payment money.")
            .font(.footnote)
            .foregroundStyle(owed > reserved ? Color.orange : Color.secondary)
          Button("Move Money", systemImage: "arrow.left.arrow.right") {
            if snapshot.readyToAssignMinor > 0 {
              onMoveMoney(.readyToAssign, .cardPayment(card.id))
            } else if let funded = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
              onMoveMoney(.envelope(funded.id), .cardPayment(card.id))
            } else {
              onMoveMoney(.cardPayment(card.id), .readyToAssign)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(snapshot.readyToAssignMinor <= 0 && reserved <= 0
            && !envelopes.contains { snapshot.available(for: $0.id) > 0 })
          .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
      }

      Section("Debt Progress") {
        LabeledContent("Amount owed", value: BudgetMoney.formatted(owed, currencyCode: currencyCode))
        ProgressView(value: debtProgress) {
          Text("Debt paid down")
        }
        .accessibilityValue("\(Int(debtProgress * 100)) percent")
        if let start = card.debtGoalStartMinor {
          Text(owed > start
            ? "Debt is \(BudgetMoney.formatted(owed - start, currencyCode: currencyCode)) above the goal’s starting balance."
            : "\(BudgetMoney.formatted(start - owed, currencyCode: currencyCode)) paid down from \(BudgetMoney.formatted(start, currencyCode: currencyCode))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          Text("Set a payoff goal to track progress from today’s balance.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let monthly = card.debtMonthlyTargetMinor {
          LabeledContent("Fund each month", value: BudgetMoney.formatted(monthly, currencyCode: currencyCode))
        }
        if let date = card.debtGoalDate {
          LabeledContent("Target date", value: date.formatted(date: .abbreviated, time: .omitted))
        }
        Button("Edit Payoff Goal", systemImage: "pencil") { showingGoalEditor = true }
      }

      Section("Recurring Transactions") {
        if cardSchedules.isEmpty {
          Text("No recurring transactions").foregroundStyle(.secondary)
        } else {
          ForEach(cardSchedules) { schedule in
            Button { onEditSchedule(schedule.id) } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(schedule.payee)
                Text("\(schedule.frequency.title) · \(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("Card Activity") {
        if cardTransactions.isEmpty {
          Text("No transactions yet").foregroundStyle(.secondary)
        } else {
          ForEach(cardTransactions) { transaction in
            Button { onSelectTransaction(transaction.id) } label: {
              TransactionRow(
                transaction: transaction, accountName: card.name,
                envelopeName: nil, currencyCode: currencyCode
              )
            }
            .buttonStyle(.plain)
          }
        }
      }

      let cardAllocations = allocations.filter {
        $0.sourceCardID == card.id || $0.targetCardID == card.id
      }.sorted { $0.date > $1.date }
      if !cardAllocations.isEmpty {
        Section("Payment Money Moves") {
          ForEach(cardAllocations) { allocation in
            LabeledContent(
              allocation.targetCardID == card.id ? "Moved in" : "Moved out",
              value: BudgetMoney.formatted(allocation.amountMinor, currencyCode: currencyCode)
            )
          }
        }
      }
    }
    .navigationTitle(card.name + " Payment")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit Card", systemImage: "pencil") { showingAccountEditor = true }
      }
    }
    .sheet(isPresented: $showingGoalEditor) {
      CardDebtGoalEditorScreen(card: card, currentDebtMinor: owed, currencyCode: currencyCode)
    }
    .sheet(isPresented: $showingAccountEditor) {
      AccountEditorScreen(currencyCode: currencyCode, account: card)
    }
  }
}
