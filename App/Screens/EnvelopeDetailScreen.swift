import SwiftUI
import SwiftData

struct EnvelopeDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  var envelope: BudgetEnvelope
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var isPastMonth: Bool = false
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var schedules: [BudgetSchedule]
  var onEdit: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var showingDelete = false
  @State private var showingHideWithBalance = false
  @State private var message: String?
  @State private var feed = TransactionFeedModel()
  @State private var hasTransactionHistory = true
  @State private var recentTransactions: [BudgetTransaction] = []

  private var envelopeAllocations: [BudgetAllocation] {
    allocations.filter { $0.sourceEnvelopeID == envelope.id || $0.targetEnvelopeID == envelope.id }
      .sorted { $0.date > $1.date }
  }

  private var envelopeSchedules: [BudgetSchedule] {
    schedules.filter { $0.envelopeID == envelope.id }
      .sorted { $0.payee < $1.payee }
  }

  private var hasHistory: Bool {
    hasTransactionHistory || !envelopeAllocations.isEmpty || !envelopeSchedules.isEmpty
      || payees.contains { $0.defaultEnvelopeID == envelope.id }
  }

  private var suggestedTarget: Int64? {
    EnvelopeFundingAdvisor().suggestedMonthlyMinor(
      envelopeID: envelope.id, transactions: recentTransactions
    )
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Available")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(BudgetMoney.formatted(snapshot.available(for: envelope.id), currencyCode: currencyCode))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(snapshot.available(for: envelope.id) < 0 ? Color.red : Color.primary)
          Text(snapshot.month.formatted(.dateTime.month(.wide).year()))
            .font(.footnote).foregroundStyle(.secondary)
          HStack(spacing: 16) {
            LabeledContent("Assigned", value: BudgetMoney.formatted(
              snapshot.assigned[envelope.id, default: 0], currencyCode: currencyCode
            ))
            LabeledContent("Activity", value: BudgetMoney.formatted(
              snapshot.activity[envelope.id, default: 0], currencyCode: currencyCode
            ))
          }
          .font(.caption)
          Button("Move Money", systemImage: "arrow.left.arrow.right") {
            let target = BudgetBucket.envelope(envelope.id)
            if snapshot.readyToAssignMinor > 0 {
              onMoveMoney(.readyToAssign, target)
            } else if let funded = envelopes.first(where: {
              $0.id != envelope.id && snapshot.available(for: $0.id) > 0
            }) {
              onMoveMoney(.envelope(funded.id), target)
            } else if let card = accounts.first(where: {
              $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0
            }) {
              onMoveMoney(.cardPayment(card.id), target)
            } else {
              onMoveMoney(target, .readyToAssign)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isPastMonth || snapshot.readyToAssignMinor <= 0
            && snapshot.available(for: envelope.id) <= 0
            && !envelopes.contains { $0.id != envelope.id && snapshot.available(for: $0.id) > 0 }
            && !accounts.contains { $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0 })
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 8)
        }
        .padding(.vertical, 8)
      }

      Section("Funding Target") {
        if let suggestedTarget {
          LabeledContent("Suggested from spending", value: BudgetMoney.formatted(suggestedTarget, currencyCode: currencyCode))
          Text("Average monthly spending across up to six completed months.")
            .font(.footnote).foregroundStyle(.secondary)
          if envelope.targetMinor != suggestedTarget && !isPastMonth {
            Button("Use Suggested Target", systemImage: "target") {
              envelope.targetMinor = suggestedTarget
              do { try modelContext.save() } catch { message = error.localizedDescription }
            }
          }
        }
        if let target = envelope.targetMinor {
          LabeledContent("Fund each month", value: BudgetMoney.formatted(target, currencyCode: currencyCode))
          if let date = envelope.targetDate {
            LabeledContent("Target date", value: date.formatted(date: .abbreviated, time: .omitted))
          }
          let remaining = max(0, target - max(0, snapshot.assigned[envelope.id, default: 0]))
          Text(remaining == 0
            ? "Monthly target met"
            : "\(BudgetMoney.formatted(remaining, currencyCode: currencyCode)) left to assign this month")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          Text("No funding target set")
            .foregroundStyle(.secondary)
        }
        Button("Edit Target", systemImage: "pencil", action: onEdit)
          .disabled(isPastMonth)
      }

      Section("Recurring Transactions") {
        if envelopeSchedules.isEmpty {
          Text("No recurring transactions")
            .foregroundStyle(.secondary)
        } else {
          ForEach(envelopeSchedules) { schedule in
            Button { onEditSchedule(schedule.id) } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(schedule.payee)
                Text("\(schedule.frequency.title) · \(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .disabled(isPastMonth)
          }
        }
      }

      Section("Transactions") {
        if feed.items.isEmpty && !feed.isLoading {
          Text("No transactions yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(feed.items) { transaction in
            Button {
              onSelectTransaction(transaction.id)
            } label: {
              TransactionSummaryRow(
                transaction: transaction,
                currencyCode: currencyCode
              )
            }
            .buttonStyle(.plain)
            .disabled(isPastMonth)
          }
          if feed.hasMore {
            ProgressView("Loading more…")
              .frame(maxWidth: .infinity)
              .onAppear { Task { await feed.loadNext() } }
          }
        }
      }

      if !envelopeAllocations.isEmpty {
        Section("Money Moves") {
          ForEach(envelopeAllocations) { allocation in
            VStack(alignment: .leading, spacing: 3) {
              LabeledContent(
                allocation.targetEnvelopeID == envelope.id ? "Moved in" : "Moved out",
                value: BudgetMoney.formatted(allocation.amountMinor, currencyCode: currencyCode)
              )
              Text(allocation.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }

      if !isPastMonth { Section {
        Button(envelope.isHidden ? "Unhide Envelope" : "Hide Envelope",
               systemImage: envelope.isHidden ? "eye" : "eye.slash") {
          if !envelope.isHidden && snapshot.available(for: envelope.id) > 0 {
            showingHideWithBalance = true
          } else {
            setHidden(!envelope.isHidden)
          }
        }
        if !hasHistory {
          Button("Delete Envelope", role: .destructive) { showingDelete = true }
        }
      } footer: {
        if hasHistory {
          Text("Hiding keeps this envelope’s balance and history. You can unhide it in Budget Settings.")
        }
      } }
    }
    .navigationTitle(envelope.name)
    .task(id: envelope.id) {
      let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: snapshot.month) ?? .distantFuture
      await feed.reload(container: modelContext.container, searchText: "", filter: TransactionFilter(),
                        scopedEnvelopeID: envelope.id, upperBound: nextMonth,
                        includeUncategorizedCount: false)
      if feed.errorMessage == nil { hasTransactionHistory = !feed.items.isEmpty }
      let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: snapshot.month) ?? .distantPast
      let envelopeID = envelope.id
      let predicate = #Predicate<BudgetTransaction> {
        $0.envelopeID == envelopeID && $0.date >= sixMonthsAgo && $0.date < nextMonth
      }
      recentTransactions = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !isPastMonth { ToolbarItem(placement: .topBarTrailing) {
        Button("Edit Envelope", systemImage: "pencil", action: onEdit)
      } }
    }
    .confirmationDialog("Delete this unused envelope?", isPresented: $showingDelete) {
      Button("Delete Envelope", role: .destructive) {
        do {
          try BudgetCommands.deleteUnusedEnvelope(envelope, in: modelContext)
          dismiss()
        } catch { message = error.localizedDescription }
      }
    } message: {
      Text("This cannot be undone.")
    }
    .confirmationDialog("Hide envelope with money?", isPresented: $showingHideWithBalance) {
      Button("Move Money First") {
        onMoveMoney(.envelope(envelope.id), .readyToAssign)
      }
      Button("Hide and Keep Balance") { setHidden(true) }
    } message: {
      Text("The balance stays in this envelope and remains part of your budget.")
    }
    .alert("Envelope", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func setHidden(_ hidden: Bool) {
    do {
      try BudgetCommands.setEnvelopeHidden(
        envelope, hidden: hidden,
        availableMinor: snapshot.available(for: envelope.id), in: modelContext
      )
      dismiss()
    } catch { message = error.localizedDescription }
  }
}
