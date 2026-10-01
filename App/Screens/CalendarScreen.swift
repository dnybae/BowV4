import SwiftUI
import SwiftData

struct CalendarScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendar) private var calendar
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
  @State private var editingSchedule: BudgetSchedule?
  @State private var monthTransactions: [BudgetTransaction] = []
  @State private var selectedSnapshot: BudgetSnapshot?
  @State private var snapshotRepository: BudgetSnapshotRepository?
  @State private var refreshVersion = 0
  @State private var isLoadingMonth = false

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
  var body: some View {
    VStack(spacing: 0) {
      CalendarMonthHeader(
        month: displayedMonth,
        onPrevious: { moveMonth(by: -1) },
        onNext: { moveMonth(by: 1) }
      )
      VStack(spacing: 0) {
        CalendarWeekdayHeader(calendar: calendar)
        CalendarMonthGrid(
          days: monthPage.days,
          selectedDate: $selectedDate,
          schedules: schedules,
          recordedDays: recordedDays,
          calendar: calendar
        )
      }
      .padding(.vertical, Bow.Space.s2)
      .bowCard()
      .padding(.horizontal, Bow.Space.s4)
      selectedDayAgenda
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn) }
        .ignoresSafeArea()
    }
    .navigationTitle("Calendar")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Today") { returnToToday() }
      }
    }
    .onAppear {
      displayedMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    }
    .onChange(of: selectedDate) { _, date in
      let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
      if month != displayedMonth { displayedMonth = month }
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

  private var daySummary: String {
    let scheduled = selectedSchedules.count
    let recorded = dayTransactions.count
    let scheduledText = scheduled == 0 ? "Nothing scheduled" : "\(scheduled) scheduled"
    let recordedText = recorded == 0 ? "nothing recorded yet" : "\(recorded) recorded"
    return "\(scheduledText), \(recordedText)"
  }

  private var selectedDayAgenda: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            Text(daySummary)
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("Spent")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
            MoneyText(minor: spentMinor, currencyCode: currencyCode)
              .font(.bowAmount)
              .monospacedDigit()
              .foregroundStyle(Bow.ink)
          }
          .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)

        if selectedSchedules.isEmpty && dayTransactions.isEmpty && !isLoadingMonth {
          ContentUnavailableView(
            "Nothing on this day",
            systemImage: "calendar",
            description: Text("Scheduled bills and recorded transactions will appear here.")
          )
          .frame(maxWidth: .infinity)
        }

        if !scheduleEntries.isEmpty || !dayTransactions.isEmpty {
          // The same rows and status lines as Spending, in one card.
          VStack(spacing: 0) {
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
          .clipShape(RoundedRectangle(cornerRadius: Bow.Radius.lg, style: .continuous))
          .bowCard()
          .padding(.horizontal, Bow.Space.s4)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 88)
    }
    .scrollsToTopOnReselect(of: .calendar)
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
    let canRecordBill = canRecord(schedule) && !isSkipped
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
      }
    ) {
      if entry.recorded == nil {
        if canRecordBill {
          Button("Record", systemImage: "plus") { onRecord(draft(for: schedule)) }
          if let occurrence = entry.occurrence {
            Button("Skip This Date", systemImage: "forward") {
              occurrence.isSkipped = true
              try? modelContext.save()
            }
          }
        }
        if isSkipped, let occurrence = entry.occurrence {
          Button("Restore Reminder", systemImage: "arrow.uturn.backward") {
            occurrence.isSkipped = false
            try? modelContext.save()
          }
        }
      }
      Button("Edit Schedule", systemImage: "calendar") { editingSchedule = schedule }
    }
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
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      selectedDate = nextDate
      displayedMonth = calendar.dateInterval(of: .month, for: nextDate)?.start ?? nextDate
    }
  }

  private func returnToToday() {
    let today = Date()
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      selectedDate = today
      displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
    }
  }

  private func loadSelectedMonth() async {
    isLoadingMonth = true
    monthTransactions = []
    selectedSnapshot = nil
    let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    let next = calendar.date(byAdding: .month, value: 1, to: month) ?? .distantFuture
    let predicate = #Predicate<BudgetTransaction> { $0.date >= month && $0.date < next }
    let transactions = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    guard !Task.isCancelled else { return }
    monthTransactions = transactions
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

private struct CalendarMonthHeader: View {
  var month: Date
  var onPrevious: () -> Void
  var onNext: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(month, format: .dateTime.month(.wide).year())
        .font(.bowLargeTitle)
        .foregroundStyle(Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      Button("Previous Month", systemImage: "chevron.left") { onPrevious() }
        .labelStyle(.iconOnly)
        .bowSecondaryButton()
      Button("Next Month", systemImage: "chevron.right") { onNext() }
        .labelStyle(.iconOnly)
        .bowSecondaryButton()
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }
}

private struct CalendarWeekdayHeader: View {
  var calendar: Calendar

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { index in
        Text(calendar.veryShortStandaloneWeekdaySymbols[
          (calendar.firstWeekday - 1 + index) % 7
        ])
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Bow.inkSoft)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 30)
  }
}

private struct CalendarMonthGrid: View {
  var days: [CalendarMonthDay]
  @Binding var selectedDate: Date
  var schedules: [BudgetSchedule]
  var recordedDays: Set<Date>
  var calendar: Calendar

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
            calendar: calendar
          )
        } else {
          Color.clear.frame(height: CalendarGridMetrics.rowHeight).accessibilityHidden(true)
        }
      }
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
  }
}

private struct CalendarMonthDayButton: View {
  var day: Date
  @Binding var selectedDate: Date
  var scheduledCount: Int
  var recorded: Bool
  var calendar: Calendar

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
          .frame(width: 36, height: 36)
          .background {
            if isSelected {
              Circle().fill(Bow.bowSolid)
            } else if isToday {
              Circle().fill(Bow.bowTint)
            }
          }
        HStack(spacing: 3) {
          if recorded { Circle().fill(Bow.bow).frame(width: 5, height: 5) }
          if scheduledCount > 0 { Circle().fill(Bow.needs).frame(width: 5, height: 5) }
        }
        .frame(height: 5)
      }
      .frame(maxWidth: .infinity)
      .frame(height: CalendarGridMetrics.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(scheduledCount) scheduled bills\(recorded ? ", recorded transactions" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private enum CalendarGridMetrics {
  static let rowHeight: CGFloat = 56
}

private struct CalendarScheduleEntry: Identifiable {
  var schedule: BudgetSchedule
  var occurrence: BudgetScheduleOccurrence?
  /// Recorded on another day, so it isn't among the selected day's transactions.
  var recorded: BudgetTransaction?

  var id: UUID { schedule.id }
}

/// One row of the day's card: the Spending row with its status tint, tappable, with a long-press menu.
private struct CalendarAgendaRow<MenuItems: View>: View {
  var model: TransactionRowModel
  var currencyCode: String
  var showsDivider: Bool
  var accessibilityHint: String = ""
  var action: () -> Void
  @ViewBuilder var menuItems: () -> MenuItems

  var body: some View {
    Button(action: action) {
      TransactionRowView(model: model, currencyCode: currencyCode)
        .padding(.horizontal, Bow.Space.s4)
        .padding(.vertical, Bow.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.state.rowStatus?.rowBackground ?? Bow.card)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .contextMenu(menuItems: menuItems)
    .accessibilityHint(accessibilityHint)
    .overlay(alignment: .bottom) {
      if showsDivider {
        Rectangle().fill(Bow.line).frame(height: 0.5).padding(.leading, Bow.Space.s4)
      }
    }
  }
}
