import SwiftUI
import SwiftData

struct PayeeDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var schedules: [BudgetSchedule]
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var profiles: [BudgetProfile]
  var payeeKey: String
  @State private var showingEdit = false
  @State private var selectedTransaction: BudgetTransaction?
  @State private var selectedSchedule: BudgetSchedule?
  @State private var entry: PayeeDirectory.Entry?
  @State private var feed = TransactionFeedModel()

  private var matchingSchedules: [BudgetSchedule] {
    schedules.filter {
      PayeeDirectory.canonicalKey(for: $0.payee, payees: payees) == payeeKey
    }.sorted { $0.startDate < $1.startDate }
  }

  private var transactionDays: [Date] {
    Array(Set(feed.items.map { Calendar.current.startOfDay(for: $0.date) }))
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
        if feed.items.isEmpty && !feed.isLoading {
          ContentUnavailableView(
            "No transactions yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Transactions for this payee will appear here.")
          )
        } else {
          ForEach(transactionDays, id: \.self) { day in
            Section(day.formatted(date: .complete, time: .omitted)) {
              ForEach(feed.items.filter {
                Calendar.current.isDate($0.date, inSameDayAs: day)
              }) { transaction in
                Button {
                  let id = transaction.id
                  let predicate = #Predicate<BudgetTransaction> { $0.id == id }
                  selectedTransaction = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first
                } label: {
                  TransactionSummaryRow(transaction: transaction, currencyCode: currencyCode)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open transaction")
              }
            }
          }
          if feed.hasMore {
            ProgressView("Loading more…")
              .frame(maxWidth: .infinity)
              .onAppear { Task { await feed.loadNext() } }
          }
        }
      }
    }
    .navigationTitle(entry?.name ?? "Payee")
    .task(id: payeeKey) {
      let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
      entry = (try? await repository.entries())?.first { $0.key == payeeKey }
      await feed.reload(container: modelContext.container, searchText: "",
                        filter: TransactionFilter(), scopedPayeeKey: payeeKey,
                        includeUncategorizedCount: false)
    }
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
