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
  @Binding var path: [BudgetRoute]
  var returnToPresentRequest: Int = 0
  var onAddGroup: () -> Void
  var onAddEnvelope: () -> Void
  var onEditEnvelope: (UUID) -> Void
  var onEditEnvelopeTarget: (UUID) -> Void
  var onImportYNAB: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onCoverOverspending: (CoverOverspendingScope) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  /// Which way the last month change went, so the title slides the same way.
  @State private var monthDirection: Edge = .trailing
  /// A small, damped follow of a horizontal swipe before it commits a month change.
  @State private var swipeOffset: CGFloat = 0
  @State private var showsMonthLoading = false
  @AppStorage("budgetCollapsedGroups") private var collapseState = BudgetGroupCollapseState()

  /// Everything on screen describes the loaded snapshot's month. `selectedMonth` can briefly be
  /// ahead of it while the next month calculates.
  private var displayedMonth: Date { snapshot.month }

  private var isShowingSelectedMonth: Bool {
    Calendar.current.isDate(snapshot.month, equalTo: selectedMonth, toGranularity: .month)
  }

  private var isPastMonth: Bool {
    (Calendar.current.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth)
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

  private var assignableEnvelope: BudgetEnvelope? {
    envelopes.first { !$0.isHidden && $0.paymentAccountID == nil }
  }

  /// Where money comes from to cover a deficit: the first funded envelope, else a card payment.
  private var deficitSource: BudgetBucket? {
    if let funded = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      return .envelope(funded.id)
    }
    return accounts.first {
      $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0
    }.map { .cardPayment($0.id) }
  }

  private var notices: [BudgetNotice] {
    BudgetNotice.notices(
      readyToAssignMinor: snapshot.readyToAssignMinor,
      overspending: overspending,
      isPastMonth: isPastMonth,
      canMoveToReadyToAssign: deficitSource != nil,
      hasEnvelopes: assignableEnvelope != nil
    )
  }

  private var canAdvance: Bool {
    // The policy needs the selected month's assignments; wait until they've loaded.
    isShowingSelectedMonth && BudgetMonthAccessPolicy().canAdvance(
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
    accounts.filter { $0.kind == .credit }.sorted { $0.name < $1.name }
  }

  var body: some View {
    List {
      BudgetOverviewSection(
        summary: summary,
        notices: notices,
        currencyCode: currencyCode,
        isPastMonth: isPastMonth,
        onSelectNotice: handle
      )

      let scheduled = scheduledTargets
      ForEach(orderedGroups) { group in
        let matching = visibleEnvelopes(in: group)
        if !matching.isEmpty {
          let key = group.id.uuidString
          Section {
            BudgetCardStack(
              groupName: group.name, items: matching,
              isCollapsed: collapseState.isCollapsed(key),
              onExpand: { toggleGroup(key) },
              route: { .envelope($0.id) },
              onOpen: open
            ) { envelope in
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
            .budgetCardStackRow()
          } header: {
            BudgetGroupHeader(
              name: group.name, count: matching.count,
              isCollapsed: collapseState.isCollapsed(key),
              onToggle: { toggleGroup(key) }
            )
          }
        }
      }

      if !creditCards.isEmpty {
        let key = BudgetGroupCollapseState.creditCardsKey
        Section {
          BudgetCardStack(
            groupName: "Credit card payments", items: creditCards,
            isCollapsed: collapseState.isCollapsed(key),
            onExpand: { toggleGroup(key) },
            route: { .cardPayment($0.id) },
            onOpen: open
          ) { card in
            CardPaymentRow(card: card, snapshot: snapshot, previousSnapshot: previousSnapshot, currencyCode: currencyCode)
          }
          .budgetCardStackRow()
        } header: {
          BudgetGroupHeader(
            name: "Credit card payments", count: creditCards.count,
            isCollapsed: collapseState.isCollapsed(key),
            onToggle: { toggleGroup(key) }
          )
        }
        .id(key)
      }

      if !isPastMonth {
        Section {
          Button("Add Envelope", systemImage: "plus", action: onAddEnvelope)
            .disabled(orderedGroups.isEmpty)
          Button("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
          Button("Import YNAB Categories", systemImage: "square.and.arrow.down", action: onImportYNAB)
        }
        .listRowBackground(Bow.card)
      }
    }
    .offset(x: swipeOffset)
    .scrollsToTopOnReselect(of: .budget)
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) {
        ZStack {
          SkyBackground(mood: skyMood)
            .id(skyMood)
            .transition(.opacity)
        }
        .bowAnimation(value: skyMood)
      }
    }
    .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.selection, trigger: displayedMonth)
    .sensoryFeedback(.selection, trigger: collapseState)
    .toolbar {
      ToolbarItem(placement: .principal) {
        BudgetMonthTitle(
          month: displayedMonth, direction: monthDirection, isLoading: showsMonthLoading
        )
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Previous Month", systemImage: "chevron.left") { changeMonth(-1) }
          .labelStyle(.iconOnly)
        Button("Next Month", systemImage: "chevron.right") { changeMonth(1) }
          .labelStyle(.iconOnly)
          .disabled(!canAdvance)
          .accessibilityHint(canAdvance ? "" : "Assign money in this month to plan the next month")
      }
    }
    .simultaneousGesture(DragGesture(minimumDistance: 30)
      .onChanged { value in
        guard !reduceMotion else { return }
        let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.6
        swipeOffset = isHorizontal ? max(-16, min(16, value.translation.width * 0.15)) : 0
      }
      .onEnded { value in
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) { swipeOffset = 0 }
        guard abs(value.translation.width) > 90,
              abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
        changeMonth(value.translation.width < 0 ? 1 : -1)
      })
    .task(id: isShowingSelectedMonth) {
      // Only show a spinner if the next month takes long enough to notice.
      showsMonthLoading = false
      guard !isShowingSelectedMonth else { return }
      try? await Task.sleep(for: .milliseconds(300))
      if !Task.isCancelled { showsMonthLoading = true }
    }
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
            onEditTarget: { onEditEnvelopeTarget(envelope.id) },
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
      monthDirection = current < selectedMonth ? .leading : .trailing
      withAnimation(Bow.motion(reduceMotion: reduceMotion)) { selectedMonth = current }
    }
    .onChange(of: lastAccessibleMonth) { _, _ in
      enforceMonthAccess()
    }
    .onAppear { enforceMonthAccess() }
  }

  private func visibleEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil && $0.groupID == group.id
    }.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  private func open(_ route: BudgetRoute) {
    // Ignore a second tap while a push is already underway.
    guard path.isEmpty else { return }
    path.append(route)
  }

  private func toggleGroup(_ key: String) {
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { collapseState.toggle(key) }
  }

  private func handle(_ notice: BudgetNotice) {
    guard notice.isActionable else { return }
    switch notice.kind {
    case .readyToAssign:
      guard let envelope = assignableEnvelope else { onAddEnvelope(); return }
      onMoveMoney(.readyToAssign, .envelope(envelope.id))
    case .deficit:
      guard let deficitSource else { return }
      onMoveMoney(deficitSource, .readyToAssign)
    case .overspent:
      onCoverOverspending(.all)
    }
  }

  private func changeMonth(_ amount: Int) {
    if amount > 0 && !canAdvance { return }
    guard let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
    monthDirection = amount > 0 ? .trailing : .leading
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { selectedMonth = next }
  }

  private func enforceMonthAccess() {
    let viewed = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
    guard viewed > lastAccessibleMonth else { return }
    monthDirection = .leading
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { selectedMonth = lastAccessibleMonth }
  }
}

/// Month and year in the navigation bar. The month slides in from the direction the user moved.
private struct BudgetMonthTitle: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var month: Date
  var direction: Edge
  var isLoading: Bool

  var body: some View {
    HStack(spacing: Bow.Space.s2) {
      VStack(spacing: 0) {
        Text(month.formatted(.dateTime.month(.wide)))
          .font(.headline)
          .foregroundStyle(Bow.ink)
        Text(month.formatted(.dateTime.year()))
          .font(.subheadline)
          .foregroundStyle(Bow.inkSoft)
      }
      .id(month)
      .transition(reduceMotion ? .opacity : .push(from: direction))
      if isLoading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Loading month")
      }
    }
    .clipped()
    .bowAnimation(value: month)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

private extension View {
  /// A group's card stack fills its List row edge to edge, with no row background or separators.
  func budgetCardStackRow() -> some View {
    self
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: Bow.Space.s1, leading: 0, bottom: Bow.Space.s1, trailing: 0))
  }
}

enum BudgetRoute: Hashable {
  case envelope(UUID)
  case cardPayment(UUID)
}

/// The top of the Budget screen: this month's totals, then banners that only appear when there's
/// something to act on.
private struct BudgetOverviewSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var summary: BudgetSummary
  var notices: [BudgetNotice]
  var currencyCode: String
  var isPastMonth: Bool
  var onSelectNotice: (BudgetNotice) -> Void

  var body: some View {
    Section {
      VStack(spacing: Bow.Space.s3) {
        metrics
        if isPastMonth {
          Text("View only · Past budget month")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
            .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: Bow.Space.s2, leading: 0, bottom: Bow.Space.s1, trailing: 0))

      ForEach(notices) { notice in
        Group {
          if notice.isActionable {
            Button { onSelectNotice(notice) } label: {
              BudgetBanner(notice: notice, currencyCode: currencyCode)
            }
            .buttonStyle(.plain)
            .accessibilityHint(notice.accessibilityHint)
          } else {
            // Informational only (past months, nothing to move): full contrast, not a dimmed button.
            BudgetBanner(notice: notice, currencyCode: currencyCode)
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: Bow.Space.s1, leading: 0, bottom: Bow.Space.s1, trailing: 0))
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
      }

      if summary.assignedInFutureMinor != 0 {
        Text("\(BudgetMoney.formatted(summary.assignedInFutureMinor, currencyCode: currencyCode)) assigned in future months")
          .font(.bowFootnote)
          .monospacedDigit()
          .foregroundStyle(Bow.inkSoft)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
    }
    .bowAnimation(value: notices.map(\.kind))
    .bowAnimation(value: isPastMonth)
  }

  private var metrics: some View {
    BowStatStrip(stats: [
      .money("Assigned", summary.assignedThisMonthMinor),
      .money("Spent", summary.spentThisMonthMinor),
      .money("Available", summary.availableMinor)
    ], currencyCode: currencyCode)
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
    let isCarryingDebt = previousOwed > previousReserved
    let status = EnvelopeStatus(
      cardOwedMinor: owed, reservedMinor: reserved,
      isCarryingDebt: isCarryingDebt, currencyCode: currencyCode
    )
    let shortfall = BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)
    BudgetStatusRow(
      name: card.name, status: status,
      accessibilityStatus: owed > reserved
        ? (isCarryingDebt ? "Carrying \(shortfall) of debt" : "Credit spending needs \(shortfall)")
        : "Ready to pay in full, \(status.pillText) set aside"
    )
  }
}
