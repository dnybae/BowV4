import SwiftUI
import SwiftData

struct CalendarScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  @Binding var selectedDate: Date
  var returnToTodayRequest: Int = 0
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onSelectTransaction: (UUID) -> Void
  @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
  /// Which way the last month change went, so the title and grid slide the same way.
  @State private var monthDirection: Edge = .trailing
  @State private var editingSchedule: BudgetSchedule?
  @State private var monthTransactions: [BudgetTransaction] = []
  @State private var selectedSnapshot: BudgetSnapshot?
  @State private var snapshotRepository: BudgetSnapshotRepository?
  /// The month `monthTransactions` belongs to. A refresh of the same month keeps showing it.
  @State private var loadedMonth: Date?
  @State private var refreshVersion = 0
  @State private var isLoadingMonth = false
  @State private var monthSwipeOffset: CGFloat = 0
  @Namespace private var selectionNamespace

  private var monthPage: CalendarMonthPage {
    CalendarMonthPage(containing: displayedMonth, calendar: calendar)
  }
  private var recordedDays: Set<Date> {
    Set(monthTransactions.map { calendar.startOfDay(for: $0.date) })
  }
  private var selectedSchedules: [BudgetSchedule] {
    schedules.filter {
      $0.isActive && ScheduleRecurrence(calendar: calendar).occurs(
        starting: $0.startDate, frequency: $0.frequency, on: selectedDate
      )
    }.sorted { $0.payee < $1.payee }
  }
  private var dayTransactions: [BudgetTransaction] {
    monthTransactions.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
      .sorted { $0.createdAt > $1.createdAt }
  }
  private var spentMinor: Int64 {
    let budgetAccountIDs = Set(accounts.filter { $0.kind == .cash || $0.kind == .credit }.map(\.id))
    return dayTransactions.reduce(0) { total, transaction in
      guard transaction.kind == .expense, !transaction.isBalanceAdjustment,
            transaction.amountMinor < 0,
            budgetAccountIDs.contains(transaction.accountID) else { return total }
      return total - transaction.amountMinor
    }
  }
  private var isShowingToday: Bool {
    calendar.isDateInToday(selectedDate)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Bow.Space.s4) {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: Bow.Space.s2) {
            Text("Choose a day")
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            DatePicker("Choose a day", selection: $selectedDate, displayedComponents: .date)
              .datePickerStyle(.compact)
              .labelsHidden()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Bow.Space.s4)
          .bowGlassCard()
        } else {
          monthCard
        }
        selectedDayHeader
        agenda
      }
      .padding(.horizontal, Bow.Space.s5)
      .padding(.top, Bow.Space.s2)
      .padding(.bottom, Bow.Space.s6)
    }
    .scrollsToTopOnReselect(of: .calendar)
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn) }
        .ignoresSafeArea()
    }
    .bowSoftScrollEdge()
    // One title: the month, in the bar, sliding the way the user moved (like Budget).
    .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        BowMonthTitle(month: displayedMonth, direction: monthDirection)
      }
      if !isShowingToday {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Today") { returnToToday() }
        }
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Previous Month", systemImage: "chevron.left") { moveMonth(by: -1) }
          .labelStyle(.iconOnly)
        Button("Next Month", systemImage: "chevron.right") { moveMonth(by: 1) }
          .labelStyle(.iconOnly)
      }
    }
    .sensoryFeedback(.selection, trigger: calendar.startOfDay(for: selectedDate))
    .onAppear {
      displayedMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    }
    .onChange(of: selectedDate) { _, date in
      let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
      if month != displayedMonth {
        monthDirection = month > displayedMonth ? .trailing : .leading
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) { displayedMonth = month }
      }
    }
    .onChange(of: returnToTodayRequest) { _, _ in
      returnToToday()
    }
    .task(id: CalendarLoadKey(month: calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate,
                              refreshVersion: refreshVersion)) {
      await loadSelectedMonth()
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .sheet(item: $editingSchedule) { schedule in
      ScheduleEditorScreen(schedule: schedule, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
    }
  }

  /// The month grid on one Liquid Glass card, like Budget's stat strip. Swipe sideways to change months.
  private var monthCard: some View {
    VStack(spacing: 0) {
      CalendarWeekdayHeader(calendar: calendar)
      CalendarMonthGrid(
        days: monthPage.days,
        selectedDate: $selectedDate,
        schedules: schedules,
        recordedDays: recordedDays,
        calendar: calendar,
        selectionNamespace: selectionNamespace
      )
      .id(displayedMonth)
      .transition(reduceMotion ? .opacity : .push(from: monthDirection))
    }
    .padding(.vertical, Bow.Space.s2)
    .clipped()
    .offset(x: monthSwipeOffset)
    .bowGlassCard()
    .bowAnimation(value: selectedDate)
    .gesture(DragGesture(minimumDistance: 24)
      .onChanged { value in
        guard !reduceMotion, abs(value.translation.width) > abs(value.translation.height) else { return }
        monthSwipeOffset = max(-16, min(16, value.translation.width * 0.15))
      }
      .onEnded { value in
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) { monthSwipeOffset = 0 }
        guard abs(value.translation.width) > 60,
              abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
        moveMonth(by: value.translation.width < 0 ? 1 : -1)
      })
  }

  private var daySummary: String {
    let scheduled = selectedSchedules.count
    let recorded = dayTransactions.count
    let scheduledText = scheduled == 0 ? "Nothing scheduled" : "\(scheduled) scheduled"
    let recordedText = recorded == 0 ? "nothing recorded yet" : "\(recorded) recorded"
    return "\(scheduledText), \(recordedText)"
  }

  private var selectedDayHeader: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s3))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    return layout {
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
          .accessibilityAddTraits(.isHeader)
        Text(daySummary)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      if !dynamicTypeSize.isAccessibilitySize { Spacer() }
      VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
        Text("Spent")
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
        MoneyText(minor: spentMinor, currencyCode: currencyCode)
          .font(.bowAmount)
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .accessibilityElement(children: .combine)
    }
    .padding(.horizontal, Bow.Space.s1)
  }

  @ViewBuilder
  private var agenda: some View {
    if selectedSchedules.isEmpty && dayTransactions.isEmpty {
      if isLoadingMonth && loadedMonth == nil {
        VStack(spacing: 0) {
          BowTransactionSkeletonRows(count: 2)
            .padding(.horizontal, Bow.Space.s4)
            .padding(.vertical, Bow.Space.s2)
        }
        .bowCard(radius: Bow.Radius.lg)
      } else {
        ContentUnavailableView(
          "Nothing on this day",
          systemImage: "calendar",
          description: Text(schedules.isEmpty
            ? "Recurring bills you schedule appear here on the days they’re due."
            : "Scheduled bills and recorded transactions will appear here.")
        )
        .frame(maxWidth: .infinity)
      }
    } else {
      // The same rows and status lines as Spending, in one card.
      LazyVStack(spacing: 0) {
        ForEach(scheduleEntries) { entry in
          scheduleRow(entry, showsDivider: entry.id != scheduleEntries.last?.id || !dayTransactions.isEmpty)
        }
        ForEach(dayTransactions) { transaction in
          CalendarAgendaRow(
            model: TransactionRowModel(
              transaction,
              accountName: accounts.first { $0.id == transaction.accountID }?.name ?? "Account",
              envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name
            ),
            currencyCode: currencyCode,
            showsDivider: transaction.id != dayTransactions.last?.id,
            action: { onSelectTransaction(transaction.id) }
          ) {
            EmptyView()
          }
        }
      }
      .bowSwipeActionsContainer()
      // No card fill: each row paints its own background, so a swiped row reveals the sky behind its actions.
      .clipShape(RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
      .shadow(color: .black.opacity(0.05), radius: 10, y: 6)
      .bowAnimation(value: scheduleEntries.map(\.id))
      .bowAnimation(value: dayTransactions.map(\.id))
    }
  }

  /// The selected day's bills, except ones already recorded and listed among the day's transactions.
  private var scheduleEntries: [CalendarScheduleEntry] {
    selectedSchedules.compactMap { schedule in
      let recorded = monthTransactions.first {
        $0.scheduleID == schedule.id
          && $0.scheduledFor.map { calendar.isDate($0, inSameDayAs: selectedDate) } == true
      }
      if let recorded, dayTransactions.contains(where: { $0.id == recorded.id }) { return nil }
      return CalendarScheduleEntry(
        schedule: schedule,
        occurrence: occurrences.first {
          $0.scheduleID == schedule.id && calendar.isDate($0.scheduledFor, inSameDayAs: selectedDate)
        },
        recorded: recorded
      )
    }
  }

  /// Bills can be recorded once they're due, and only with an account.
  private func canRecord(_ schedule: BudgetSchedule) -> Bool {
    selectedDate <= Date() && schedule.accountID != nil
  }

  private func scheduleRow(_ entry: CalendarScheduleEntry, showsDivider: Bool) -> some View {
    let schedule = entry.schedule
    let isSkipped = entry.occurrence?.isSkipped == true
    let canRecordBill = canRecord(schedule) && !isSkipped && entry.recorded == nil
    let skippable = canRecordBill ? entry.occurrence : nil
    return CalendarAgendaRow(
      model: scheduleModel(entry),
      currencyCode: currencyCode,
      showsDivider: showsDivider,
      accessibilityHint: entry.recorded != nil ? "Opens the recorded transaction"
        : canRecordBill ? "Opens the bill to record it" : "Opens the schedule",
      action: {
        if let recorded = entry.recorded {
          onSelectTransaction(recorded.id)
        } else if canRecordBill {
          onRecord(draft(for: schedule))
        } else {
          editingSchedule = schedule
        }
      },
      onRecord: canRecordBill ? { onRecord(draft(for: schedule)) } : nil,
      onSkip: skippable.map { occurrence in { setSkipped(occurrence, true) } }
    ) {
      if entry.recorded == nil {
        if canRecordBill {
          Button("Record", systemImage: "plus") { onRecord(draft(for: schedule)) }
          if let occurrence = entry.occurrence {
            Button("Skip This Date", systemImage: "forward") { setSkipped(occurrence, true) }
          }
        }
        if isSkipped, let occurrence = entry.occurrence {
          Button("Restore Reminder", systemImage: "arrow.uturn.backward") { setSkipped(occurrence, false) }
        }
      }
      Button("Edit Schedule", systemImage: "calendar") { editingSchedule = schedule }
    }
  }

  private func setSkipped(_ occurrence: BudgetScheduleOccurrence, _ skipped: Bool) {
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { occurrence.isSkipped = skipped }
    try? modelContext.save()
  }

  /// A bill as a Spending row. The status line carries what the old row said: skipped,
  /// recorded, or whether its envelope can cover it.
  private func scheduleModel(_ entry: CalendarScheduleEntry) -> TransactionRowModel {
    let schedule = entry.schedule
    let state: TransactionRowModel.State
    if entry.recorded != nil {
      state = .normal
    } else if entry.occurrence?.isSkipped == true {
      state = .pending("Skipped")
    } else if schedule.kind == .transfer && schedule.envelopeID == nil {
      state = .scheduled("Scheduled")
    } else if schedule.envelopeID == nil {
      state = .scheduled("Scheduled · Choose an envelope")
    } else if let selectedSnapshot, let envelopeID = schedule.envelopeID {
      let shortfall = max(0, schedule.amountMinor - max(0, selectedSnapshot.available(for: envelopeID)))
      state = .scheduled(shortfall > 0
        ? "Scheduled · Envelope short \(BudgetMoney.formatted(shortfall, currencyCode: currencyCode))"
        : "Scheduled")
    } else {
      state = .scheduled("Scheduled")
    }
    return TransactionRowModel(
      id: "scheduled-\(schedule.id)",
      title: schedule.payee.isEmpty ? "Scheduled bill" : schedule.payee,
      logoName: schedule.kind == .transfer ? "" : schedule.payee,
      merchantDomain: nil,
      kind: schedule.kind,
      accountName: accounts.first { $0.id == schedule.accountID }?.name ?? "Account",
      envelopeName: envelopes.first { $0.id == schedule.envelopeID }?.name,
      amountMinor: -schedule.amountMinor,
      state: state
    )
  }

  private func draft(for schedule: BudgetSchedule) -> ScheduledTransactionDraft {
    ScheduledTransactionDraft(
      scheduleID: schedule.id, scheduledFor: selectedDate,
      accountID: schedule.accountID, transferAccountID: schedule.transferAccountID,
      envelopeID: schedule.envelopeID, kind: schedule.kind,
      amountMinor: schedule.amountMinor, payee: schedule.payee,
      notes: schedule.notes, date: selectedDate
    )
  }

  private func moveMonth(by offset: Int) {
    guard let nextDate = monthPage.adjacentSelection(from: selectedDate, by: offset) else { return }
    monthDirection = offset > 0 ? .trailing : .leading
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      selectedDate = nextDate
      displayedMonth = calendar.dateInterval(of: .month, for: nextDate)?.start ?? nextDate
    }
  }

  private func returnToToday() {
    let today = Date()
    let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    monthDirection = month < displayedMonth ? .leading : .trailing
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      selectedDate = today
      displayedMonth = month
    }
  }

  private func loadSelectedMonth() async {
    let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    // A refresh of the month on screen keeps its rows until the new ones arrive, so nothing flashes.
    if loadedMonth != month {
      monthTransactions = []
      selectedSnapshot = nil
      loadedMonth = nil
    }
    isLoadingMonth = true
    let next = calendar.date(byAdding: .month, value: 1, to: month) ?? .distantFuture
    let predicate = #Predicate<BudgetTransaction> { $0.date >= month && $0.date < next }
    let transactions = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    guard !Task.isCancelled else { return }
    monthTransactions = transactions
    loadedMonth = month
    if snapshotRepository == nil {
      snapshotRepository = BudgetSnapshotRepository(modelContainer: modelContext.container)
    }
    if let snapshotRepository {
      await snapshotRepository.invalidate()
      guard !Task.isCancelled else { return }
      let snapshot = try? await snapshotRepository.snapshot(month: month)
      guard !Task.isCancelled else { return }
      selectedSnapshot = snapshot
    }
    isLoadingMonth = false
  }
}

private struct CalendarLoadKey: Hashable {
  var month: Date
  var refreshVersion: Int
}

private struct CalendarWeekdayHeader: View {
  var calendar: Calendar

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { index in
        Text(calendar.veryShortStandaloneWeekdaySymbols[
          (calendar.firstWeekday - 1 + index) % 7
        ])
        .font(.bowCaption.weight(.semibold))
        .foregroundStyle(Bow.inkSoft)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, Bow.Space.s4)
    .padding(.vertical, Bow.Space.s2)
  }
}

private struct CalendarMonthGrid: View {
  var days: [CalendarMonthDay]
  @Binding var selectedDate: Date
  var schedules: [BudgetSchedule]
  var recordedDays: Set<Date>
  var calendar: Calendar
  var selectionNamespace: Namespace.ID
  @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 56

  var body: some View {
    let recurrence = ScheduleRecurrence(calendar: calendar)
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
      ForEach(days) { slot in
        if let day = slot.date {
          let scheduled = schedules.reduce(0) { count, schedule in
            count + (schedule.isActive && recurrence.occurs(
              starting: schedule.startDate, frequency: schedule.frequency, on: day
            ) ? 1 : 0)
          }
          CalendarMonthDayButton(
            day: day,
            selectedDate: $selectedDate,
            scheduledCount: scheduled,
            recorded: recordedDays.contains(day),
            calendar: calendar,
            selectionNamespace: selectionNamespace,
            rowHeight: rowHeight
          )
        } else {
          Color.clear.frame(height: rowHeight).accessibilityHidden(true)
        }
      }
    }
    .padding(.horizontal, Bow.Space.s4)
    .frame(maxWidth: .infinity)
  }
}

private struct CalendarMonthDayButton: View {
  var day: Date
  @Binding var selectedDate: Date
  var scheduledCount: Int
  var recorded: Bool
  var calendar: Calendar
  var selectionNamespace: Namespace.ID
  var rowHeight: CGFloat
  @ScaledMetric(relativeTo: .title3) private var circle: CGFloat = 36
  @ScaledMetric(relativeTo: .title3) private var dot: CGFloat = 5

  var body: some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    Button {
      selectedDate = day
    } label: {
      VStack(spacing: 2) {
        Text(day.formatted(.dateTime.day()))
          .font(.system(.title3, design: .rounded, weight: isSelected || isToday ? .bold : .medium))
          .foregroundStyle(isSelected ? Bow.onBow : (isToday ? Bow.bowInk : Bow.ink))
          .minimumScaleFactor(0.6)
          .frame(width: circle, height: circle)
          .background {
            // One selection circle that glides between days.
            if isSelected {
              Circle().fill(Bow.bowSolid)
                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            } else if isToday {
              Circle().fill(Bow.bowTint)
            }
          }
        HStack(spacing: 3) {
          if recorded { Circle().fill(Bow.bow).frame(width: dot, height: dot) }
          if scheduledCount > 0 { Circle().fill(Bow.needs).frame(width: dot, height: dot) }
        }
        .frame(height: dot)
      }
      .frame(maxWidth: .infinity)
      .frame(height: rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(scheduledCount) scheduled bills\(recorded ? ", recorded transactions" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct CalendarScheduleEntry: Identifiable {
  var schedule: BudgetSchedule
  var occurrence: BudgetScheduleOccurrence?
  /// Recorded on another day, so it isn't among the selected day's transactions.
  var recorded: BudgetTransaction?

  var id: UUID { schedule.id }
}

/// One row of the day's card: the Spending row with its status tint, tappable, with a long-press
/// menu and (for bills) the same swipe actions as Spending.
private struct CalendarAgendaRow<MenuItems: View>: View {
  var model: TransactionRowModel
  var currencyCode: String
  var showsDivider: Bool
  var accessibilityHint: String = ""
  var action: () -> Void
  var onRecord: (() -> Void)? = nil
  var onSkip: (() -> Void)? = nil
  @ViewBuilder var menuItems: () -> MenuItems

  var body: some View {
    Button(action: action) {
      TransactionRowView(model: model, currencyCode: currencyCode)
        .padding(.horizontal, Bow.Space.s4)
        .padding(.vertical, Bow.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.state.rowStatus?.rowBackground ?? Bow.card)
        // The divider slides with the row, so nothing is drawn behind the revealed actions.
        .overlay(alignment: .bottom) {
          if showsDivider {
            Rectangle().fill(Bow.line).frame(height: 0.5).padding(.leading, Bow.Space.s4)
          }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.bowRowPress)
    .contentShape(.contextMenuPreview, .rect(cornerRadius: Bow.Radius.md))
    .contextMenu(menuItems: menuItems)
    .swipeActions(edge: .leading) {
      if let onRecord {
        Button("Record", systemImage: "plus", action: onRecord)
          .tint(.accentColor)
      }
    }
    .swipeActions(edge: .trailing) {
      if let onSkip {
        Button("Skip", systemImage: "forward", action: onSkip)
      }
    }
    .accessibilityHint(accessibilityHint)
    // Swipeable rows clip to their container shape; a rectangle keeps them full-width bands, as in Spending.
    .containerShape(.rect)
  }
}
