import SwiftUI
import SwiftData

struct EnvelopeDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var groups: [BudgetGroup]
  var envelope: BudgetEnvelope
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var isPastMonth: Bool = false
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var schedules: [BudgetSchedule]
  var onEdit: () -> Void
  var onEditTarget: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onCoverOverspending: () -> Void
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

  private var scheduledContributions: [ScheduleTargetContribution] {
    ScheduleTargetCalculator().contributions(for: envelope.id, schedules: schedules, month: snapshot.month)
  }

  private var scheduledTotal: Int64 {
    scheduledContributions.reduce(0) { $0 + $1.totalMinor }
  }

  private var totalTarget: Int64? {
    let total = (envelope.targetMinor ?? 0) + scheduledTotal
    return total > 0 ? total : nil
  }

  /// Spending the scheduled bills don't already cover, so accepting it doesn't double count them.
  private var suggestedTarget: Int64? {
    guard let average = EnvelopeFundingAdvisor().suggestedMonthlyMinor(
      envelopeID: envelope.id, transactions: recentTransactions
    ) else { return nil }
    let remainder = average - scheduledTotal
    return remainder > 0 ? remainder : nil
  }

  private var availableMinor: Int64 { snapshot.available(for: envelope.id) }

  private var status: EnvelopeStatus {
    EnvelopeStatus(
      availableMinor: availableMinor,
      assignedMinor: snapshot.assigned[envelope.id, default: 0],
      activityMinor: snapshot.activity[envelope.id, default: 0],
      monthlyTargetMinor: totalTarget, currencyCode: currencyCode
    )
  }

  /// Progress toward this month's target; without a target, the same fill as the Budget row.
  private var heroFraction: Double {
    guard availableMinor >= 0, let totalTarget else { return status.ringFraction }
    return min(1, Double(max(0, snapshot.assigned[envelope.id, default: 0])) / Double(totalTarget))
  }

  private var heroCaption: String {
    if let totalTarget {
      let assigned = BudgetMoney.formatted(max(0, snapshot.assigned[envelope.id, default: 0]), currencyCode: currencyCode)
      return "\(assigned) of \(BudgetMoney.formatted(totalTarget, currencyCode: currencyCode))"
    }
    return snapshot.month.formatted(.dateTime.month(.wide).year())
  }

  private var statusHeadline: (title: String, message: String)? {
    switch status.state {
    case .over:
      return ("Over by \(BudgetMoney.formatted(-availableMinor, currencyCode: currencyCode))",
              "Cover it from another envelope.")
    case .needs:
      return (status.pillText, "to reach this month’s target")
    case .funded where totalTarget != nil:
      return ("Target met", "This month’s target is fully assigned.")
    case .funded, .empty:
      return nil
    }
  }

  /// "Set target" until the envelope has a target of its own.
  private var targetActionTitle: String {
    (envelope.targetMinor ?? 0) > 0 ? "Edit target" : "Set target"
  }

  private var canMoveMoneyIn: Bool {
    if availableMinor < 0 {
      // Covering can draw from Ready to Assign or another envelope, not card payment money.
      return !isPastMonth && (snapshot.readyToAssignMinor > 0
        || envelopes.contains { $0.id != envelope.id && $0.paymentAccountID == nil && snapshot.available(for: $0.id) > 0 })
    }
    return !isPastMonth && (snapshot.readyToAssignMinor > 0
      || availableMinor > 0
      || envelopes.contains { $0.id != envelope.id && snapshot.available(for: $0.id) > 0 }
      || accounts.contains { $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0 })
  }

  private var groupName: String {
    groups.first { $0.id == envelope.groupID }?.name ?? ""
  }

  var body: some View {
    List {
      Section {
        VStack(spacing: Bow.Space.s4) {
          // Small enough that the funding target starts on the first screen.
          GlowRing(fraction: heroFraction, color: status.state.ring, size: 176) {
            VStack(spacing: Bow.Space.s1) {
              Text("Available")
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
              MoneyText(minor: availableMinor, currencyCode: currencyCode)
                .bowHeroFont()
                .monospacedDigit()
                .foregroundStyle(Bow.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
              Text(heroCaption)
                .font(.bowFootnote)
                .monospacedDigit()
                .foregroundStyle(Bow.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: 150)
          }
          .accessibilityElement(children: .combine)

          if let statusHeadline {
            VStack(spacing: 2) {
              Text(statusHeadline.title)
                .font(.bowTitle)
                .monospacedDigit()
                .foregroundStyle(Bow.ink)
              Text(statusHeadline.message)
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
          }

          actionTiles

          BowStatStrip(stats: [
            .money("Assigned", snapshot.assigned[envelope.id, default: 0]),
            .money("Spent", max(0, -(snapshot.activity[envelope.id, default: 0]))),
            .money("Carried in", snapshot.carriedIn(for: envelope.id))
          ], currencyCode: currencyCode)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
      }

      Section {
        if let totalTarget {
          LabeledContent("Fund this month") {
            MoneyText(minor: totalTarget, currencyCode: currencyCode)
              .fontDesign(.rounded).monospacedDigit()
          }
            .fontWeight(.semibold)
          if !scheduledContributions.isEmpty {
            LabeledContent("Your target") {
              MoneyText(minor: envelope.targetMinor ?? 0, currencyCode: currencyCode)
                .fontDesign(.rounded).monospacedDigit()
            }
            ForEach(scheduledContributions) { contribution in
              ScheduledTargetRow(contribution: contribution, currencyCode: currencyCode)
            }
          }
          if let date = envelope.targetDate {
            LabeledContent("Target date", value: date.formatted(date: .abbreviated, time: .omitted))
          }
          let remaining = max(0, totalTarget - max(0, snapshot.assigned[envelope.id, default: 0]))
          Text(remaining == 0
            ? "Monthly target met"
            : "\(BudgetMoney.formatted(remaining, currencyCode: currencyCode)) left to assign this month")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        } else {
          Text("No target yet")
            .foregroundStyle(Bow.inkSoft)
        }
        if let suggestedTarget {
          LabeledContent("Suggested from spending") {
            MoneyText(minor: suggestedTarget, currencyCode: currencyCode)
              .fontDesign(.rounded).monospacedDigit()
          }
          if envelope.targetMinor != suggestedTarget && !isPastMonth {
            Button {
              envelope.targetMinor = suggestedTarget
              do { try modelContext.save() } catch { message = error.localizedDescription }
            } label: {
              Label("Use \(BudgetMoney.formatted(suggestedTarget, currencyCode: currencyCode)) as the target",
                    systemImage: "checkmark.circle")
                .labelStyle(.bowTile)
            }
          }
        }
      } header: {
        Text("Funding target")
      } footer: {
        if !scheduledContributions.isEmpty {
          Text("Scheduled transactions add \(BudgetMoney.formatted(scheduledTotal, currencyCode: currencyCode)) to this month’s target, on top of your own.")
        } else if suggestedTarget != nil {
          Text("Suggestion is average monthly spending across up to six completed months.")
        }
      }
      .listRowBackground(Bow.card)

      Section("Recurring transactions") {
        if envelopeSchedules.isEmpty {
          Text("No recurring transactions")
            .foregroundStyle(Bow.inkSoft)
        } else {
          ForEach(envelopeSchedules) { schedule in
            Button { onEditSchedule(schedule.id) } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(schedule.payee)
                Text("\(schedule.frequency.title) · \(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))")
                  .font(.bowSubhead)
                  .foregroundStyle(Bow.inkSoft)
              }
            }
            .disabled(isPastMonth)
          }
        }
      }
      .listRowBackground(Bow.card)

      if feed.items.isEmpty && !feed.isLoading {
        Section("Transactions") {
          Text("No transactions yet")
            .foregroundStyle(Bow.inkSoft)
        }
        .listRowBackground(Bow.card)
      } else {
        ForEach(TransactionDateGroup.make(feed.items)) { group in
          Section(group.title) {
            ForEach(group.items) { transaction in
              Button {
                onSelectTransaction(transaction.id)
              } label: {
                TransactionRowView(
                  model: TransactionRowModel(transaction),
                  currencyCode: currencyCode, options: .hidesEnvelope
                )
              }
              .buttonStyle(.plain)
              .disabled(isPastMonth)
            }
          }
          .listRowBackground(Bow.card)
        }
        if feed.hasMore {
          Section {
            ProgressView("Loading more…")
              .frame(maxWidth: .infinity)
              .onAppear { Task { await feed.loadNext() } }
          }
          .listRowBackground(Bow.card)
        }
      }

      if !envelopeAllocations.isEmpty {
        Section("Money moves") {
          ForEach(envelopeAllocations) { allocation in
            VStack(alignment: .leading, spacing: 3) {
              LabeledContent(allocation.targetEnvelopeID == envelope.id ? "Moved in" : "Moved out") {
                MoneyText(minor: allocation.amountMinor, currencyCode: currencyCode)
                  .fontDesign(.rounded).monospacedDigit()
              }
              Text(allocation.date.formatted(date: .abbreviated, time: .omitted))
                .font(.bowSubhead).foregroundStyle(Bow.inkSoft)
            }
          }
        }
        .listRowBackground(Bow.card)
      }

    }
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: status.state.sky) }
    }
    .navigationTitle(envelope.name)
    .navigationSubtitle(groupName)
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
        Menu("Edit Envelope", systemImage: "pencil") {
          Button("Edit Envelope", systemImage: "pencil", action: onEdit)
          Button(envelope.isHidden ? "Unhide Envelope" : "Hide Envelope",
                 systemImage: envelope.isHidden ? "eye" : "eye.slash") {
            if !envelope.isHidden && snapshot.available(for: envelope.id) > 0 {
              showingHideWithBalance = true
            } else {
              setHidden(!envelope.isHidden)
            }
          }
          if !hasHistory {
            Button("Delete Envelope", systemImage: "trash", role: .destructive) { showingDelete = true }
          }
        }
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

  /// Assign / Move out / target; when overspent, Cover leads instead.
  private var actionTiles: some View {
    BowActionTileRow {
      if availableMinor < 0 {
        BowActionTile("Cover", systemImage: "bolt", isProminent: true, action: onCoverOverspending)
          .disabled(!canMoveMoneyIn)
        BowActionTile("Assign", systemImage: "plus", action: moveMoneyIn)
          .disabled(!canMoveMoneyIn)
      } else {
        BowActionTile("Assign", systemImage: "plus", isProminent: true, action: moveMoneyIn)
          .disabled(!canMoveMoneyIn)
        BowActionTile("Move out", systemImage: "arrow.up.arrow.down") {
          onMoveMoney(.envelope(envelope.id), .readyToAssign)
        }
        .disabled(availableMinor <= 0 || isPastMonth)
      }
      BowActionTile(targetActionTitle, systemImage: "dollarsign", action: onEditTarget)
        .disabled(isPastMonth)
    }
  }

  /// Opens Move Money into this envelope from the most useful source, as before the redesign.
  private func moveMoneyIn() {
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
