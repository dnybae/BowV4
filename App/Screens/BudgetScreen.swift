import SwiftUI

struct BudgetScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var currencyCode: String
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var allocations: [BudgetAllocation]
  var schedules: [BudgetSchedule]
  var snapshot: BudgetSnapshot
  var previousSnapshot: BudgetSnapshot? = nil
  @Binding var selectedMonth: Date
  var returnToPresentRequest: Int = 0
  var onAddGroup: () -> Void
  var onAddEnvelope: () -> Void
  var onEditEnvelope: (UUID) -> Void
  var onImportYNAB: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onCoverOverspending: (CoverOverspendingScope) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var searchText = ""

  private var isPastMonth: Bool {
    (Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth)
      < (Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date())
  }

  private var summary: BudgetSummary {
    BudgetSummary(
      snapshot: snapshot, envelopes: envelopes,
      accounts: accounts, allocations: allocations
    )
  }

  private var overspending: OverspendingSummary {
    OverspendingSummary(snapshot: snapshot, envelopes: envelopes, groups: groups)
  }

  private var canAdvance: Bool {
    BudgetMonthAccessPolicy().canAdvance(
      from: selectedMonth, today: Date(), assignedMinor: summary.assignedThisMonthMinor
    )
  }

  private var lastAccessibleMonth: Date {
    BudgetMonthAccessPolicy().lastAccessibleMonth(
      today: Date(), funding: allocations.map(\.monthFundingItem)
    )
  }

  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted { $0.sortOrder == $1.sortOrder
      ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
      : $0.sortOrder < $1.sortOrder }
  }

  /// Same monthly target the envelope detail screen shows: the user's target plus scheduled bills.
  private var scheduledTargets: [UUID: Int64] {
    ScheduleTargetCalculator().totalsByEnvelope(schedules: schedules, month: snapshot.month)
  }

  private func monthlyTarget(for envelope: BudgetEnvelope, scheduled: [UUID: Int64]) -> Int64? {
    let total = (envelope.targetMinor ?? 0) + scheduled[envelope.id, default: 0]
    return total > 0 ? total : nil
  }

  private var skyMood: SkyMood {
    snapshot.readyToAssignMinor < 0 ? .coral : .dawn
  }

  private var creditCards: [BudgetAccount] {
    accounts.filter { $0.kind == .credit &&
      (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        || "credit card payments".localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.name < $1.name }
  }

  var body: some View {
    ScrollViewReader { _ in
      List {
        BudgetOverviewSection(
          summary: summary,
          overspending: overspending,
          currencyCode: currencyCode,
          canMove: !isPastMonth && (snapshot.readyToAssignMinor > 0
            || envelopes.contains { snapshot.available(for: $0.id) > 0 }
            || accounts.contains { $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0 }),
          isPastMonth: isPastMonth,
          onAssign: assignMoney,
          onCoverOverspending: { onCoverOverspending(.all) }
        )

        let scheduled = scheduledTargets
        ForEach(orderedGroups) { group in
          let matching = visibleEnvelopes(in: group)
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in
                NavigationLink(value: BudgetRoute.envelope(envelope.id)) {
                  EnvelopeBudgetRow(
                    name: envelope.name,
                    availableMinor: snapshot.available(for: envelope.id),
                    cashOverspentMinor: snapshot.cashShortfall[envelope.id, default: 0],
                    creditOverspentMinor: snapshot.creditShortfall[envelope.id, default: 0],
                    assignedMinor: snapshot.assigned[envelope.id, default: 0],
                    activityMinor: snapshot.activity[envelope.id, default: 0],
                    monthlyTargetMinor: monthlyTarget(for: envelope, scheduled: scheduled),
                    currencyCode: currencyCode
                  )
                }
              }
            }
            .listRowBackground(Bow.card)
          }
        }

        if !searchText.isEmpty
          && orderedGroups.allSatisfy({ visibleEnvelopes(in: $0).isEmpty })
          && creditCards.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }

        if !creditCards.isEmpty {
          Section("Credit card payments") {
            ForEach(creditCards) { card in
              NavigationLink(value: BudgetRoute.cardPayment(card.id)) {
                CardPaymentRow(card: card, snapshot: snapshot, previousSnapshot: previousSnapshot, currencyCode: currencyCode)
              }
            }
          }
          .listRowBackground(Bow.card)
          .id("credit-card-payments")
        }

        if searchText.isEmpty && !isPastMonth {
          Section {
            Button("Add Envelope", systemImage: "plus", action: onAddEnvelope)
              .disabled(orderedGroups.isEmpty)
            Button("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
            Button("Import YNAB Categories", systemImage: "square.and.arrow.down", action: onImportYNAB)
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground {
        Bow.mist.overlay(alignment: .top) { SkyBackground(mood: skyMood) }
      }
      .animation(reduceMotion ? nil : .snappy, value: selectedMonth)
      .searchable(text: $searchText, prompt: "Search envelopes or groups")
      .navigationTitle(selectedMonth.formatted(.dateTime.month(.wide)))
      .navigationSubtitle(selectedMonth.formatted(.dateTime.year()))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Previous Month", systemImage: "chevron.left") { changeMonth(-1) }
            .labelStyle(.iconOnly)
          Button("Next Month", systemImage: "chevron.right") { changeMonth(1) }
            .labelStyle(.iconOnly)
            .disabled(!canAdvance)
            .accessibilityHint(canAdvance ? "" : "Assign money in this month to plan the next month")
        }
      }
      .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { value in
        guard abs(value.translation.width) > 90,
              abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
        changeMonth(value.translation.width < 0 ? 1 : -1)
      })
      .navigationDestination(for: BudgetRoute.self) { route in
        switch route {
        case .envelope(let id):
          if let envelope = envelopes.first(where: { $0.id == id }) {
            EnvelopeDetailScreen(
              envelope: envelope, currencyCode: currencyCode, snapshot: snapshot,
              isPastMonth: isPastMonth,
              accounts: accounts, envelopes: envelopes,
              allocations: allocations, schedules: schedules,
              onEdit: { onEditEnvelope(envelope.id) },
              onMoveMoney: onMoveMoney,
              onCoverOverspending: { onCoverOverspending(.envelope(envelope.id)) },
              onSelectTransaction: onSelectTransaction,
              onEditSchedule: onEditSchedule
            )
          }
        case .cardPayment(let id):
          if let card = accounts.first(where: { $0.id == id }) {
            CardPaymentDetailScreen(
              card: card, currencyCode: currencyCode, snapshot: snapshot,
              previousSnapshot: previousSnapshot,
              isPastMonth: isPastMonth,
              accounts: accounts,
              envelopes: envelopes,
              allocations: allocations, schedules: schedules,
              onMoveMoney: onMoveMoney,
              onCoverOverspending: { onCoverOverspending(.card(card.id)) },
              onSelectTransaction: onSelectTransaction,
              onEditSchedule: onEditSchedule
            )
          }
        }
      }
      .onChange(of: returnToPresentRequest) { _, _ in
        let current = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = current }
      }
      .onChange(of: lastAccessibleMonth) { _, _ in
        enforceMonthAccess()
      }
      .onAppear { enforceMonthAccess() }
    }
  }

  private func visibleEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil && $0.groupID == group.id
        && (searchText.isEmpty || group.name.localizedCaseInsensitiveContains(searchText)
          || $0.name.localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  private func assignMoney() {
    guard !isPastMonth else { return }
    let first = envelopes.first(where: { !$0.isHidden && $0.paymentAccountID == nil })
    if snapshot.readyToAssignMinor > 0 {
      guard let first else { onAddEnvelope(); return }
      onMoveMoney(.readyToAssign, .envelope(first.id))
      return
    }
    let source: BudgetBucket?
    if let funded = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      source = .envelope(funded.id)
    } else if let card = accounts.first(where: {
      $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0
    }) {
      source = .cardPayment(card.id)
    } else {
      source = nil
    }
    guard let source else { return }
    onMoveMoney(source, .readyToAssign)
  }

  private func changeMonth(_ amount: Int) {
    if amount > 0 && !canAdvance { return }
    guard let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
    withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = next }
  }

  private func enforceMonthAccess() {
    let viewed = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
    guard viewed > lastAccessibleMonth else { return }
    withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = lastAccessibleMonth }
  }
}

enum BudgetRoute: Hashable {
  case envelope(UUID)
  case cardPayment(UUID)
}

private struct BudgetOverviewSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var summary: BudgetSummary
  var overspending: OverspendingSummary
  var currencyCode: String
  var canMove: Bool
  var isPastMonth: Bool
  var onAssign: () -> Void
  var onCoverOverspending: () -> Void

  private var isDeficit: Bool { summary.readyToAssignMinor < 0 }

  private var overspentTitle: String {
    overspending.items.count == 1 ? "1 overspent envelope" : "\(overspending.items.count) overspent envelopes"
  }

  private var overspentMessage: String {
    let total = BudgetMoney.formatted(overspending.totalMinor, currencyCode: currencyCode)
    if isPastMonth { return "\(total) was left uncovered when this month ended." }
    switch (overspending.cashMinor > 0, overspending.creditMinor > 0) {
    case (true, true): return "\(total) over. Cover it to keep next month’s budget and your card payments on track."
    case (false, true): return "\(total) over on credit cards. Cover it so your card payments stay funded."
    default: return "\(total) over. Cover it now or it comes out of next month’s Ready to Assign."
    }
  }

  var body: some View {
    Section {
      VStack(spacing: Bow.Space.s5) {
        GlowRing(fraction: summary.assignedShare, color: isDeficit ? Bow.over : Bow.bow) {
          VStack(spacing: Bow.Space.s1) {
            Text("Ready to Assign")
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
            Text(BudgetMoney.formatted(summary.readyToAssignMinor, currencyCode: currencyCode))
              .font(.bowHero)
              .monospacedDigit()
              .foregroundStyle(isDeficit ? Bow.overInk : Bow.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.4)
          }
          .frame(maxWidth: 180)
        }
        .accessibilityElement(children: .combine)
        // Rounded down so the ring never claims 100% while money is still waiting for a job.
        .accessibilityValue("\(Int((summary.assignedShare * 100).rounded(.down))) percent assigned")

        if isDeficit || isPastMonth {
          Text(isDeficit ? "Move money back or add cash to cover this deficit." : "View only · Past budget month")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
            .multilineTextAlignment(.center)
        }

        Button(summary.readyToAssignMinor > 0 ? "Assign money" : "Move money", action: onAssign)
          .bowPrimaryButton()
          .disabled(!canMove)

        HStack(spacing: Bow.Space.s2) {
          metric("Assigned", amount: summary.assignedThisMonthMinor)
          metric("Spent", amount: summary.spentThisMonthMinor)
          metric("Available", amount: summary.availableMinor)
        }
        .padding(.vertical, Bow.Space.s3)
        .padding(.horizontal, Bow.Space.s2)
        .glassEffect(.regular, in: .rect(cornerRadius: Bow.Radius.lg))

        if summary.assignedInFutureMinor != 0 {
          Text("\(BudgetMoney.formatted(summary.assignedInFutureMinor, currencyCode: currencyCode)) assigned in future months")
            .font(.bowFootnote)
            .monospacedDigit()
            .foregroundStyle(Bow.inkSoft)
            .multilineTextAlignment(.center)
        }
      }
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))

      if !overspending.isEmpty {
        Button(action: onCoverOverspending) {
          NoteCard(symbol: "exclamationmark.triangle.fill", title: overspentTitle, message: overspentMessage)
        }
        .buttonStyle(.plain)
        .disabled(isPastMonth)
        .accessibilityHint(isPastMonth ? "" : "Choose envelopes to cover the overspending")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: Bow.Space.s2, leading: 0, bottom: Bow.Space.s2, trailing: 0))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .animation(reduceMotion ? nil : .snappy, value: overspending.items.map(\.envelopeID))
  }

  private func metric(_ title: String, amount: Int64) -> some View {
    VStack(spacing: 2) {
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
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

private struct CardPaymentRow: View {
  var card: BudgetAccount
  var snapshot: BudgetSnapshot
  var previousSnapshot: BudgetSnapshot?
  var currencyCode: String

  var body: some View {
    let owed = max(0, -snapshot.accountBalances[card.id, default: 0])
    let reserved = max(0, snapshot.paymentAvailable[card.id, default: 0])
    let previousOwed = max(0, -(previousSnapshot?.accountBalances[card.id] ?? 0))
    let previousReserved = max(0, previousSnapshot?.paymentAvailable[card.id] ?? 0)
    let status = EnvelopeStatus(
      cardOwedMinor: owed, reservedMinor: reserved,
      isCarryingDebt: previousOwed > previousReserved, currencyCode: currencyCode
    )
    HStack(spacing: Bow.Space.s3) {
      StatusRing(fraction: status.ringFraction, state: status.state)
      VStack(alignment: .leading, spacing: 2) {
        Text(card.name)
          .font(.bowBody)
          .foregroundStyle(Bow.ink)
        Text(owed > reserved
          ? (previousOwed > previousReserved
            ? "Carrying \(BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)) of debt"
            : "Credit spending needs funding")
          : "Ready to pay in full")
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: Bow.Space.s2)
      StatusPill(text: status.pillText, state: status.state)
    }
    .frame(minHeight: 44)
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .combine)
  }
}
