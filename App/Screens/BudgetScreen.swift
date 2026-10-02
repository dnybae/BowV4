import SwiftUI
import SwiftData

struct BudgetScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.modelContext) private var modelContext
  @State private var envelopeToHide: BudgetEnvelope?
  @State private var actionError: String?
  @Environment(\.bowToasts) private var toasts
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
  var onAddAccount: () -> Void
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
  /// Set while a horizontal swipe is changing months, so lifting a finger over a card doesn't open it.
  @State private var isSwipingMonth = false
  @Namespace private var zoomNamespace
  @State private var showingAssignment = false
  @State private var customAssignment: UUID?
  @State private var collapseState = BudgetGroupCollapseState.saved

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

  /// Visible envelopes in the order the Budget screen shows them.
  private var budgetOrderedEnvelopes: [BudgetEnvelope] {
    orderedGroups.flatMap { visibleEnvelopes(in: $0) }
  }

  /// Where Assign sends money first: the first envelope still short of this month's target,
  /// else the first envelope on screen.
  private var assignableEnvelope: BudgetEnvelope? {
    let scheduled = scheduledTargets
    let ordered = budgetOrderedEnvelopes
    return ordered.first { envelope in
      guard let target = monthlyTarget(for: envelope, scheduled: scheduled) else { return false }
      return snapshot.assigned[envelope.id, default: 0] < target
    } ?? ordered.first
  }

  /// Where money comes from to cover a deficit: the first funded envelope on screen, else a card payment.
  private var deficitSource: BudgetBucket? {
    if let funded = budgetOrderedEnvelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      return .envelope(funded.id)
    }
    return creditCards.first {
      snapshot.paymentAvailable[$0.id, default: 0] > 0
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
      from: selectedMonth, today: Date(), assignedMinor: summary.assignedThisMonthMinor,
      readyToAssignMinor: snapshot.readyToAssignMinor
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
    EnvelopeTargetPlanner().monthlyMinor(
      for: envelope, scheduledMinor: scheduled[envelope.id, default: 0], snapshot: snapshot
    )
  }

  private var skyMood: SkyMood {
    snapshot.readyToAssignMinor < 0 ? .coral : .dawn
  }

  private var hasOpenAccount: Bool {
    accounts.contains { $0.closedAt == nil }
  }

  /// The setup steps stay until there's an account, an envelope and money assigned.
  private var showsSetup: Bool {
    !isPastMonth && (!hasOpenAccount || !hasBudgetEnvelopes || allocations.isEmpty)
  }

  private var hasBudgetEnvelopes: Bool {
    envelopes.contains { !$0.isHidden && $0.paymentAccountID == nil }
  }

  /// Ready to Assign for the month on screen. The month is part of the value, so switching
  /// months never counts as reaching zero.
  private var readyToAssignState: ReadyToAssignState {
    ReadyToAssignState(month: snapshot.month, minor: snapshot.readyToAssignMinor)
  }

  private var creditCards: [BudgetAccount] {
    accounts.filter { $0.kind == .credit && $0.closedAt == nil }.sorted { $0.name < $1.name }
  }

  var body: some View {
    // A ScrollView, not a List: List resizes rows on its own timing, which fought the card
    // stacks' collapse animation.
    ScrollView {
      VStack(alignment: .leading, spacing: Bow.Space.s6) {
        screenContent
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Bow.Space.s5)
      .padding(.top, Bow.Space.s3)
      .padding(.bottom, Bow.Space.s8)
    }
    .font(.bowHeadline)
    .offset(x: swipeOffset)
    .scrollsToTopOnReselect(of: .budget)
    .background {
      Bow.mist.overlay(alignment: .top) {
        ZStack {
          SkyBackground(mood: skyMood)
            .id(skyMood)
            .transition(.opacity)
        }
        .bowAnimation(value: skyMood)
      }
      .ignoresSafeArea()
    }
    .bowSoftScrollEdge()
    .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
    .navigationBarTitleDisplayMode(.inline)
    // Ticks when the user changes months, not later when the month finishes loading.
    .sensoryFeedback(.selection, trigger: selectedMonth)
    .sensoryFeedback(.selection, trigger: collapseState)
    .sensoryFeedback(trigger: readyToAssignState, readyToAssignFeedback)
    .sheet(isPresented: $showingAssignment, onDismiss: {
      if let id = customAssignment {
        customAssignment = nil
        onMoveMoney(.readyToAssign, .envelope(id))
      }
    }) {
      AssignMoneyScreen(month: displayedMonth, currencyCode: currencyCode) { id in
        customAssignment = id
        showingAssignment = false
      }
    }
    .bowConfirmationDialog("Hide envelope?", item: $envelopeToHide) { envelope in
      Button("Hide Envelope", role: .destructive) {
        do {
          let undo = try UndoableChanges.setHidden(envelope, hidden: true,
            availableMinor: snapshot.available(for: envelope.id), in: modelContext)
          toasts?.show(.deleted("Hidden · \(envelope.name)", undo: undo))
        } catch { actionError = error.localizedDescription }
      }
      Button("Cancel", role: .cancel) {}
    } message: { envelope in
      Text("\(envelope.name) and its history stay in your budget. Any assigned money stays in this envelope. You can unhide it in Manage Envelopes.")
    }
    .bowErrorAlert("Couldn’t Hide Envelope", message: $actionError)
    .toolbar {
      ToolbarItem(placement: .principal) {
        BowMonthTitle(
          month: displayedMonth, direction: monthDirection, isLoading: showsMonthLoading
        )
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button { changeMonth(-1) } label: { BowToolbarLabel("Previous Month", systemImage: "chevron.left") }
          .labelStyle(.iconOnly)
        Button { changeMonth(1) } label: { BowToolbarLabel("Next Month", systemImage: "chevron.right") }
          .labelStyle(.iconOnly)
          .accessibilityHint(canAdvance ? "" : "Assign money or add income in this month to plan the next one")
      }
      .bowHighVisibilityPriority()
    }
    .simultaneousGesture(DragGesture(minimumDistance: 30)
      .onChanged { value in
        let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.6
        if isHorizontal { isSwipingMonth = true }
        guard !reduceMotion else { return }
        swipeOffset = isHorizontal ? max(-16, min(16, value.translation.width * 0.15)) : 0
      }
      .onEnded { value in
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) { swipeOffset = 0 }
        // Let a card's release (which can land just after this) see the swipe, then clear it.
        Task {
          try? await Task.sleep(for: .milliseconds(250))
          isSwipingMonth = false
        }
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
      destination(for: route)
    }
    .onChange(of: returnToPresentRequest) { _, _ in
      let current = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
      monthDirection = current < selectedMonth ? .leading : .trailing
      withAnimation(Bow.motion(reduceMotion: reduceMotion)) { selectedMonth = current }
    }
  }

  /// Success when Ready to Assign reaches zero within the month on screen.
  private func readyToAssignFeedback(old: ReadyToAssignState, new: ReadyToAssignState) -> SensoryFeedback? {
    guard old.month == new.month, old.minor != 0, new.minor == 0, !isPastMonth else { return nil }
    return .success
  }

  @ViewBuilder
  private func destination(for route: BudgetRoute) -> some View {
    switch route {
    case .manageEnvelopes:
      EnvelopeManagementScreen()
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
        .navigationTransition(.zoom(sourceID: route, in: zoomNamespace))
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
        .navigationTransition(.zoom(sourceID: route, in: zoomNamespace))
      }
    }
  }

  @ViewBuilder
  private var screenContent: some View {
    BudgetOverviewSection(
      summary: summary,
      notices: notices,
      currencyCode: currencyCode,
      isPastMonth: isPastMonth,
      onSelectNotice: handle
    )

    if showsSetup {
      BudgetSetupCard(
        hasAccount: hasOpenAccount,
        hasEnvelopes: hasBudgetEnvelopes,
        hasAssigned: !allocations.isEmpty,
        onAddAccount: onAddAccount,
        onAddEnvelopes: orderedGroups.isEmpty ? onAddGroup : onAddEnvelope,
        onImportYNAB: onImportYNAB,
        onAssign: {
          if let envelope = assignableEnvelope { onMoveMoney(.readyToAssign, .envelope(envelope.id)) }
        }
      )
      .transition(.opacity)
    }

    let scheduled = scheduledTargets
    ForEach(orderedGroups) { group in
      let matching = visibleEnvelopes(in: group)
      if !matching.isEmpty {
        let key = group.id.uuidString
        VStack(alignment: .leading, spacing: Bow.Space.s2) {
          BowGroupHeader(
            name: group.name, count: matching.count,
            isCollapsed: collapseState.isCollapsed(key),
            onToggle: { toggleGroup(key) }
          )
          .padding(.leading, Bow.Space.s1)

          BowCardStack(
            items: matching,
            isCollapsed: collapseState.isCollapsed(key),
            collapsedLabel: Text("\(group.name), ^[\(matching.count) envelope](inflect: true), collapsed"),
            onExpand: { toggleGroup(key) }
          ) { envelope in
            budgetCard(.envelope(envelope.id)) {
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
      }
    }

    if !creditCards.isEmpty {
      let key = BudgetGroupCollapseState.creditCardsKey
      VStack(alignment: .leading, spacing: Bow.Space.s2) {
        BowGroupHeader(
          name: "Credit card payments", count: creditCards.count,
          isCollapsed: collapseState.isCollapsed(key),
          onToggle: { toggleGroup(key) }
        )
        .padding(.leading, Bow.Space.s1)

        BowCardStack(
          items: creditCards,
          isCollapsed: collapseState.isCollapsed(key),
          collapsedLabel: Text("Credit card payments, ^[\(creditCards.count) card](inflect: true), collapsed"),
          onExpand: { toggleGroup(key) }
        ) { card in
          budgetCard(.cardPayment(card.id)) {
            CardPaymentRow(card: card, snapshot: snapshot, previousSnapshot: previousSnapshot, currencyCode: currencyCode)
          }
        }
      }
      .id(key)
    }

    if !isPastMonth && hasBudgetEnvelopes {
      VStack(spacing: 0) {
        actionRow("Add Envelope", systemImage: "plus", isDisabled: orderedGroups.isEmpty, action: onAddEnvelope)
        Divider().padding(.leading, Bow.Space.s4)
        actionRow("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
        Divider().padding(.leading, Bow.Space.s4)
        actionRow("Manage Envelopes", systemImage: "slider.horizontal.3") { open(.manageEnvelopes) }
      }
      .clipShape(RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
      .bowCard()
    }
  }

  private func visibleEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil && $0.groupID == group.id
    }.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  private func open(_ route: BudgetRoute) {
    // Ignore a second tap while a push is already underway, and a finger lifted after a month swipe.
    guard path.isEmpty, !isSwipingMonth else { return }
    path.append(route)
  }

  /// One envelope or card payment card, opening its route. A button rather than a
  /// NavigationLink, so `open` can ignore a finger lifted at the end of a month swipe.
  private func budgetCard<Row: View>(_ route: BudgetRoute, @ViewBuilder row: () -> Row) -> some View {
    let content = row()
    return Button { open(route) } label: {
      BowItemCard { content }
    }
    .buttonStyle(.bowPress)
    .matchedTransitionSource(id: route, in: zoomNamespace)
    .contextMenu { if !isPastMonth { quickActions(for: route) } }
  }

  /// Long-press shortcuts to what the detail screen's tiles do.
  @ViewBuilder
  private func quickActions(for route: BudgetRoute) -> some View {
    switch route {
    case .envelope(let id):
      let available = snapshot.available(for: id)
      if available < 0 {
        Button("Cover Overspending", systemImage: "bolt") { onCoverOverspending(.envelope(id)) }
      }
      Button("Assign", systemImage: "plus") { onMoveMoney(.readyToAssign, .envelope(id)) }
      if available > 0 {
        Button("Move Out", systemImage: "arrow.up.arrow.down") { onMoveMoney(.envelope(id), .readyToAssign) }
      }
      Divider()
      Button("Edit Target", systemImage: "dollarsign") { onEditEnvelopeTarget(id) }
      Button("Edit Envelope", systemImage: "pencil") { onEditEnvelope(id) }
      if available >= 0 {
        Button("Hide Envelope", systemImage: "eye.slash") {
          envelopeToHide = envelopes.first { $0.id == id }
        }
      }
    case .manageEnvelopes:
      EmptyView()
    case .cardPayment(let id):
      Button("Assign to Payment", systemImage: "plus") { onMoveMoney(.readyToAssign, .cardPayment(id)) }
      if snapshot.paymentAvailable[id, default: 0] > 0 {
        Button("Move Out", systemImage: "arrow.up.arrow.down") { onMoveMoney(.cardPayment(id), .readyToAssign) }
      }
    }
  }

  /// A tinted row in the card of actions at the bottom of the screen, like a List button row.
  private func actionRow(
    _ title: String, systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        // A fixed column, so every title starts at the same edge.
        Image(systemName: systemImage).frame(width: 28)
      }
      .font(.bowHeadline)
      .foregroundStyle(.tint)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .padding(.horizontal, Bow.Space.s4)
      .contentShape(.rect)
    }
    .buttonStyle(.bowRowPress)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.4 : 1)
  }

  private func toggleGroup(_ key: String) {
    withAnimation(Bow.stackMotion(reduceMotion: reduceMotion)) { collapseState.toggle(key) }
    collapseState.save()
  }

  private func handle(_ notice: BudgetNotice) {
    guard notice.isActionable else { return }
    switch notice.kind {
    case .readyToAssign:
      guard !budgetOrderedEnvelopes.isEmpty else { onAddEnvelope(); return }
      showingAssignment = true
    case .deficit:
      guard let deficitSource else { return }
      onMoveMoney(deficitSource, .readyToAssign)
    case .overspent:
      onCoverOverspending(.all)
    }
  }

  private func changeMonth(_ amount: Int) {
    if amount > 0 && !canAdvance {
      // Say why rather than ignoring the tap.
      if isShowingSelectedMonth {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        toasts?.show(BowToast(
          message: "Assign money in \(displayedMonth.formatted(.dateTime.month(.wide))) to start planning \(next.formatted(.dateTime.month(.wide)))",
          systemImage: "calendar.badge.clock", feedback: .quiet
        ))
      }
      return
    }
    guard let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
    monthDirection = amount > 0 ? .trailing : .leading
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { selectedMonth = next }
  }
}

/// Ready to Assign tied to its month, so the success haptic only fires within one month.
private struct ReadyToAssignState: Equatable {
  var month: Date
  var minor: Int64
}

enum BudgetRoute: Hashable {
  case envelope(UUID)
  case cardPayment(UUID)
  /// Reorder, hide, rename and browse ideas, without leaving Budget for Settings.
  case manageEnvelopes
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

  /// Nothing waiting and something assigned: the month's money all has a job.
  private var isFullyAssigned: Bool {
    !isPastMonth && summary.readyToAssignMinor == 0 && summary.assignedThisMonthMinor > 0
  }

  var body: some View {
    VStack(spacing: Bow.Space.s2) {
      // Most urgent first, above the totals: Ready to Assign is the screen's focal point.
      ForEach(notices) { notice in
        Group {
          if notice.isActionable {
            Button { onSelectNotice(notice) } label: {
              banner(notice)
            }
            .buttonStyle(.bowPress)
            .accessibilityHint(notice.accessibilityHint)
          } else {
            // Informational only (past months, nothing to move): full contrast, not a dimmed button.
            banner(notice)
          }
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
      }

      if isFullyAssigned {
        BudgetAllAssignedBanner()
          .transition(.opacity)
      }

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

      if summary.assignedInFutureMinor != 0 {
        HStack(spacing: Bow.Space.s1) {
          MoneyText(minor: summary.assignedInFutureMinor, currencyCode: currencyCode)
          Text("assigned in future months")
        }
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .padding(.vertical, Bow.Space.s2)
      }
    }
    .bowAnimation(value: notices.map(\.kind))
    .bowAnimation(value: isFullyAssigned)
    .bowAnimation(value: isPastMonth)
  }

  private func banner(_ notice: BudgetNotice) -> some View {
    BudgetBanner(
      notice: notice, currencyCode: currencyCode,
      assignedShare: notice.kind == .readyToAssign ? summary.assignedShare : nil
    )
  }

  private var metrics: some View {
    BowStatStrip(stats: [
      .money("Assigned", summary.assignedThisMonthMinor),
      .money("Spent", summary.spentThisMonthMinor),
      .money("Available", summary.availableMinor)
    ], currencyCode: currencyCode)
  }
}

/// Shown when Ready to Assign reaches zero: calm, green, and not a button.
private struct BudgetAllAssignedBanner: View {
  @State private var bounce = 0

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      Image(systemName: "checkmark.seal.fill")
        .bowScaledIcon(frame: 34, glyph: 18)
        .foregroundStyle(Bow.fundedInk)
        .symbolEffect(.bounce, value: bounce)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Every dollar has a job")
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
        Text("All of this month’s money is assigned.")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: 0)
    }
    .padding(Bow.Space.s4)
    .background(Bow.fundedTint, in: RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
    .accessibilityElement(children: .combine)
    .onAppear { bounce += 1 }
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
