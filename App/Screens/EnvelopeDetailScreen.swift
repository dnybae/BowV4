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

  private var primaryActionTitle: String {
    if availableMinor < 0 { return "Cover overspending" }
    return snapshot.readyToAssignMinor > 0 ? "Assign money" : "Move money"
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
          GlowRing(fraction: heroFraction, color: status.state.ring, size: 200) {
            VStack(spacing: Bow.Space.s1) {
              Text("Available")
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
              Text(BudgetMoney.formatted(availableMinor, currencyCode: currencyCode))
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
            .frame(maxWidth: 170)
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

          HStack(spacing: Bow.Space.s3) {
            Button(primaryActionTitle, action: availableMinor < 0 ? onCoverOverspending : moveMoneyIn)
              .bowPrimaryButton()
              .disabled(!canMoveMoneyIn)
            if availableMinor > 0 && !isPastMonth {
              Button("Move out") { onMoveMoney(.envelope(envelope.id), .readyToAssign) }
                .bowSecondaryButton()
            }
          }

          HStack(spacing: Bow.Space.s3) {
            statTile("Assigned", amount: snapshot.assigned[envelope.id, default: 0])
            statTile("Spent", amount: max(0, -(snapshot.activity[envelope.id, default: 0])))
            statTile("Carried in", amount: snapshot.carriedIn(for: envelope.id))
          }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
      }

      Section {
        if let totalTarget {
          LabeledContent("Fund this month") {
            Text(BudgetMoney.formatted(totalTarget, currencyCode: currencyCode))
              .fontDesign(.rounded).monospacedDigit()
          }
            .fontWeight(.semibold)
          if !scheduledContributions.isEmpty {
            LabeledContent("Your target") {
              Text(BudgetMoney.formatted(envelope.targetMinor ?? 0, currencyCode: currencyCode))
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
            .font(.footnote)
            .foregroundStyle(Bow.inkSoft)
        } else {
          Text("No funding target set")
            .foregroundStyle(Bow.inkSoft)
        }
        if let suggestedTarget {
          LabeledContent("Suggested from spending") {
              Text(BudgetMoney.formatted(suggestedTarget, currencyCode: currencyCode))
                .fontDesign(.rounded).monospacedDigit()
            }
          if envelope.targetMinor != suggestedTarget && !isPastMonth {
            Button("Use Suggested Target", systemImage: "target") {
              envelope.targetMinor = suggestedTarget
              do { try modelContext.save() } catch { message = error.localizedDescription }
            }
          }
        }
        Button("Edit Target", systemImage: "pencil", action: onEdit)
          .disabled(isPastMonth)
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
                  .font(.subheadline)
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
                TransactionSummaryRow(
                  transaction: transaction,
                  currencyCode: currencyCode,
                  showsDate: false
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
                Text(BudgetMoney.formatted(allocation.amountMinor, currencyCode: currencyCode))
                  .fontDesign(.rounded).monospacedDigit()
              }
              Text(allocation.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline).foregroundStyle(Bow.inkSoft)
            }
          }
        }
        .listRowBackground(Bow.card)
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
      }
      .listRowBackground(Bow.card) }
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

  private func statTile(_ title: String, amount: Int64) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
      Text(BudgetMoney.formatted(amount, currencyCode: currencyCode))
        .font(.bowAmount)
        .monospacedDigit()
        .foregroundStyle(Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Bow.Space.s3)
    .bowCard(radius: Bow.Radius.md)
    .accessibilityElement(children: .combine)
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
