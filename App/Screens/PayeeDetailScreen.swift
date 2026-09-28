import SwiftUI
import SwiftData

struct PayeeDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var payees: [BudgetPayee]
  @Query private var transactions: [BudgetTransaction]
  @Query private var schedules: [BudgetSchedule]
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var profiles: [BudgetProfile]
  var payeeKey: String
  @State private var showingEdit = false
  @State private var selectedTransaction: BudgetTransaction?
  @State private var selectedSchedule: BudgetSchedule?

  private var entry: PayeeDirectory.Entry? {
    PayeeDirectory.entries(payees: payees, transactions: transactions, schedules: schedules)
      .first { $0.key == payeeKey }
  }

  private var matchingTransactions: [BudgetTransaction] {
    transactions.filter {
      PayeeDirectory.canonicalKey(for: $0.payee, payees: payees) == payeeKey
    }.sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
  }

  private var matchingSchedules: [BudgetSchedule] {
    schedules.filter {
      PayeeDirectory.canonicalKey(for: $0.payee, payees: payees) == payeeKey
    }.sorted { $0.startDate < $1.startDate }
  }

  private var transactionDays: [Date] {
    Array(Set(matchingTransactions.map { Calendar.current.startOfDay(for: $0.date) }))
      .sorted(by: >)
  }

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  var body: some View {
    List {
      if let entry {
        if let payee = payees.first(where: { $0.id == entry.ruleID }),
           let envelope = envelopes.first(where: { $0.id == payee.defaultEnvelopeID }) {
          Section("Default Envelope") {
            LabeledContent("Envelope", value: envelope.name)
          }
        }
        if !matchingSchedules.isEmpty {
          Section("Scheduled") {
            ForEach(matchingSchedules) { schedule in
              Button {
                selectedSchedule = schedule
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(schedule.payee).foregroundStyle(.primary)
                    Text(schedule.frequency.title)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        if matchingTransactions.isEmpty {
          ContentUnavailableView(
            "No transactions yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Transactions for this payee will appear here.")
          )
        } else {
          ForEach(transactionDays, id: \.self) { day in
            Section(day.formatted(date: .complete, time: .omitted)) {
              ForEach(matchingTransactions.filter {
                Calendar.current.isDate($0.date, inSameDayAs: day)
              }) { transaction in
                Button {
                  selectedTransaction = transaction
                } label: {
                  TransactionRow(
                    transaction: transaction,
                    accountName: accounts.first { $0.id == transaction.accountID }?.name ?? "Account",
                    envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name,
                    currencyCode: currencyCode
                  )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open transaction")
              }
            }
          }
        }
      }
    }
    .navigationTitle(entry?.name ?? "Payee")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { showingEdit = true }
          .disabled(entry == nil)
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let entry {
        PayeeEditorScreen(
          entry: entry,
          payee: payees.first { $0.id == entry.ruleID }
        ) { dismiss() }
      }
    }
    .sheet(item: $selectedTransaction) { transaction in
      TransactionEditorScreen(
        transaction: transaction,
        accounts: accounts,
        envelopes: envelopes,
        payees: payees,
        currencyCode: currencyCode
      )
    }
    .sheet(item: $selectedSchedule) { schedule in
      ScheduleEditorScreen(
        schedule: schedule,
        accounts: accounts,
        envelopes: envelopes,
        currencyCode: currencyCode
      )
    }
  }
}
