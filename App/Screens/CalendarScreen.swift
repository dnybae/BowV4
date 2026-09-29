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
  @State private var timeline = CalendarTimelineWindow(centeredOn: Date())
  @State private var calendarScrollID = UUID()
  @State private var scrollDay: CalendarDaySlot.ID? = .day(
    Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
  )
  @State private var visibleMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
  @State private var calendarVisibleRect: CGRect = .zero
  @State private var hasPlacedInitialScroll = false
  @State private var isPlacingInitialScroll = false
  @State private var isTodayVisible = true
  @State private var isCalendarScrolling = false
  @State private var isExtendingTimeline = false
  @State private var editingSchedule: BudgetSchedule?
  @State private var recordedDays: Set<Date> = []
  @State private var monthTransactions: [BudgetTransaction] = []
  @State private var selectedSnapshot: BudgetSnapshot?
  @State private var snapshotRepository: BudgetSnapshotRepository?
  @State private var refreshVersion = 0
  @State private var isLoadingMonth = false

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
    ScrollViewReader { scrollProxy in
      VStack(spacing: 0) {
        CalendarWeekdayHeader(calendar: calendar)
        Divider()
        ScrollView(.vertical) {
          CalendarTimelineGrid(
            days: timeline.days,
            selectedDate: $selectedDate,
            schedules: schedules,
            recordedDays: recordedDays,
            calendar: calendar
          )
        }
        .id(calendarScrollID)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollDay, anchor: .top)
        .onScrollGeometryChange(for: CalendarScrollMetrics.self) { geometry in
          CalendarScrollMetrics(
            visibleRect: geometry.visibleRect,
            contentHeight: geometry.contentSize.height
          )
        } action: { _, metrics in
          calendarVisibleRect = metrics.visibleRect
          if !hasPlacedInitialScroll,
             metrics.contentHeight > metrics.visibleRect.height {
            placeInitialScroll(using: scrollProxy)
          } else {
            updateVisibleDays(in: metrics.visibleRect, scrollProxy: scrollProxy)
          }
        }
        .onAppear {
          if !timeline.contains(selectedDate) {
            timeline = CalendarTimelineWindow(centeredOn: selectedDate, calendar: calendar)
          }
          visibleMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        }
        .onScrollPhaseChange { _, phase in
          isCalendarScrolling = phase.isScrolling
          if !phase.isScrolling {
            updateVisibleDays(in: calendarVisibleRect, scrollProxy: scrollProxy)
          }
        }
        Divider()
        selectedDayAgenda
          .frame(height: 230)
      }
      .navigationTitle(visibleMonth.formatted(.dateTime.month(.wide).year()))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if !calendar.isDateInToday(selectedDate) || !isTodayVisible {
            Button("Today") { returnToToday(using: scrollProxy) }
          }
        }
      }
      .onChange(of: returnToTodayRequest) { _, _ in
        returnToToday(using: scrollProxy)
      }
      .task(id: CalendarLoadKey(month: calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate,
                                refreshVersion: refreshVersion)) {
        await loadSelectedMonth()
      }
      .task(id: CalendarDayMarkLoadKey(firstMonth: timeline.firstMonth,
                                       endMonth: timeline.endMonth,
                                       refreshVersion: refreshVersion)) {
        await loadRecordedDays()
      }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        refreshVersion += 1
      }
      .sheet(item: $editingSchedule) { schedule in
        ScheduleEditorScreen(schedule: schedule, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
      }
    }
  }

  private var selectedDayAgenda: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
              .font(.headline)
            Text("\(selectedSchedules.count) scheduled · \(dayTransactions.count) recorded")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 4) {
            Text("Spent on this day")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(BudgetMoney.formatted(spentMinor, currencyCode: currencyCode))
              .font(.headline)
          }
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

        if let selectedSnapshot { ForEach(selectedSchedules) { schedule in
          CalendarScheduleRow(
            schedule: schedule, selectedDate: selectedDate,
            occurrence: occurrences.first {
              $0.scheduleID == schedule.id
                && calendar.isDate($0.scheduledFor, inSameDayAs: selectedDate)
            },
            transactions: monthTransactions, snapshot: selectedSnapshot,
            currencyCode: currencyCode,
            onEdit: { editingSchedule = schedule },
            onRecord: onRecord,
            onRestore: { occurrence in
              occurrence.isSkipped = false
              try? modelContext.save()
            },
            onSelectTransaction: onSelectTransaction
          )
        } }

        if !dayTransactions.isEmpty {
          Text("Transactions")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
          ForEach(dayTransactions) { transaction in
            Button { onSelectTransaction(transaction.id) } label: {
              TransactionRow(
                transaction: transaction,
                accountName: accounts.first { $0.id == transaction.accountID }?.name ?? "Account",
                envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name,
                currencyCode: currencyCode
              )
              .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 88)
    }
  }

  private func placeInitialScroll(using proxy: ScrollViewProxy) {
    guard !hasPlacedInitialScroll, !isPlacingInitialScroll else { return }
    isPlacingInitialScroll = true
    let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    visibleMonth = month
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 120_000_000)
      let target = CalendarDaySlot.ID.day(month)
      scrollDay = target
      proxy.scrollTo(target, anchor: .top)
      hasPlacedInitialScroll = true
      isPlacingInitialScroll = false
      updateVisibleDays(in: calendarVisibleRect, scrollProxy: proxy)
    }
  }

  private func returnToToday(using proxy: ScrollViewProxy) {
    let today = Date()
    let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    selectedDate = today
    visibleMonth = month
    isTodayVisible = true
    let target = CalendarDaySlot.ID.day(month)
    if !timeline.contains(today) {
      hasPlacedInitialScroll = false
      isPlacingInitialScroll = false
      calendarVisibleRect = .zero
      timeline = CalendarTimelineWindow(centeredOn: today, calendar: calendar)
      scrollDay = target
      calendarScrollID = UUID()
    } else {
      withAnimation(reduceMotion ? nil : .snappy) {
        scrollDay = target
        proxy.scrollTo(target, anchor: .top)
      }
    }
  }

  private func updateVisibleDays(in rect: CGRect, scrollProxy: ScrollViewProxy) {
    guard hasPlacedInitialScroll, rect.width > 0, rect.height > 0, !timeline.days.isEmpty else { return }
    let rowHeight = CalendarGridMetrics.rowHeight
    let rowCount = (timeline.days.count + 6) / 7
    let firstRow = max(0, Int(floor(rect.minY / rowHeight)))
    let lastRow = min(rowCount - 1, Int(ceil(rect.maxY / rowHeight)) - 1)
    guard firstRow <= lastRow else { return }
    var first: Date?
    var last: Date?
    var monthAreas: [Date: CGFloat] = [:]
    for row in firstRow...lastRow {
      let rowTop = CGFloat(row) * rowHeight
      let visibleHeight = max(0, min(rowTop + rowHeight, rect.maxY) - max(rowTop, rect.minY))
      guard visibleHeight > 0 else { continue }
      for index in (row * 7)..<min(row * 7 + 7, timeline.days.count) {
        guard let date = timeline.days[index].date else { continue }
        if first == nil { first = date }
        last = date
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        monthAreas[month, default: 0] += visibleHeight
      }
    }
    guard let first, let last else { return }
    let today = calendar.startOfDay(for: Date())
    isTodayVisible = first <= today && today <= last
    if let largest = monthAreas.max(by: { $0.value < $1.value }),
       largest.value > monthAreas[visibleMonth, default: 0] + 1 {
      visibleMonth = largest.key
    }
    guard !isCalendarScrolling, !isExtendingTimeline else { return }
    if let direction = timeline.directionToExtend(near: first), direction == .earlier {
      extendTimeline(.earlier, anchoredAt: first, using: scrollProxy)
    } else if let direction = timeline.directionToExtend(near: last), direction == .later {
      extendTimeline(.later, anchoredAt: first, using: scrollProxy)
    }
  }

  private func extendTimeline(
    _ direction: CalendarTimelineWindow.Direction,
    anchoredAt visibleDate: Date,
    using proxy: ScrollViewProxy
  ) {
    isExtendingTimeline = true
    let anchor = CalendarDaySlot.ID.day(visibleDate)
    Task { @MainActor in
      await Task.yield()
      timeline.extend(direction)
      await Task.yield()
      scrollDay = anchor
      proxy.scrollTo(anchor, anchor: .top)
      isExtendingTimeline = false
    }
  }

  private func loadRecordedDays() async {
    let first = timeline.firstMonth
    let end = timeline.endMonth
    let predicate = #Predicate<BudgetTransaction> { $0.date >= first && $0.date < end }
    var descriptor = FetchDescriptor<BudgetTransaction>(predicate: predicate)
    descriptor.propertiesToFetch = [\.date]
    let dates = (try? modelContext.fetch(descriptor))?.map(\.date) ?? []
    guard !Task.isCancelled else { return }
    recordedDays = Set(dates.map { calendar.startOfDay(for: $0) })
  }

  private func loadSelectedMonth() async {
    isLoadingMonth = true
    let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    let next = calendar.date(byAdding: .month, value: 1, to: month) ?? .distantFuture
    let predicate = #Predicate<BudgetTransaction> { $0.date >= month && $0.date < next }
    monthTransactions = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    if snapshotRepository == nil {
      snapshotRepository = BudgetSnapshotRepository(modelContainer: modelContext.container)
    }
    if let snapshotRepository {
      await snapshotRepository.invalidate()
      selectedSnapshot = try? await snapshotRepository.snapshot(month: month)
    }
    isLoadingMonth = false
  }
}

private struct CalendarLoadKey: Hashable {
  var month: Date
  var refreshVersion: Int
}

private struct CalendarDayMarkLoadKey: Hashable {
  var firstMonth: Date
  var endMonth: Date
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
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 30)
  }
}

private struct CalendarTimelineGrid: View {
  var days: [CalendarDaySlot]
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
          CalendarTimelineDayButton(
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
    .scrollTargetLayout()
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
  }
}

private struct CalendarTimelineDayButton: View {
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
      VStack(spacing: 3) {
        Text(day.formatted(.dateTime.day()))
          .font(.system(.callout, design: .rounded, weight: isSelected ? .bold : .medium))
          .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : (isToday ? Color.red : Color.primary))
          .frame(width: 30, height: 30)
          .background {
            if isSelected { Circle().fill(Color.primary) }
          }
        Circle()
          .fill(scheduledCount > 0 || recorded ? Color.accentColor : Color.clear)
          .frame(width: 5, height: 5)
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
  static let rowHeight: CGFloat = 44
}

private struct CalendarScrollMetrics: Equatable {
  var visibleRect: CGRect
  var contentHeight: CGFloat
}

private struct CalendarScheduleRow: View {
  var schedule: BudgetSchedule
  var selectedDate: Date
  var occurrence: BudgetScheduleOccurrence?
  var transactions: [BudgetTransaction]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onEdit: () -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onRestore: (BudgetScheduleOccurrence) -> Void
  var onSelectTransaction: (UUID) -> Void

  private var recordedTransaction: BudgetTransaction? {
    transactions.first {
      $0.scheduleID == schedule.id
        && $0.scheduledFor.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } == true
    }
  }

  var body: some View {
    let available = schedule.envelopeID.map { snapshot.available(for: $0) } ?? 0
    let shortfall = max(0, schedule.amountMinor - max(0, available))
    VStack(alignment: .leading, spacing: 8) {
      Button(action: onEdit) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(schedule.payee).font(.headline)
            Text(schedule.frequency.title + (recordedTransaction != nil
              ? " · Recorded" : occurrence?.isSkipped == true ? " · Skipped" : " · Expected"))
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))
            .font(.subheadline.weight(.semibold))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if recordedTransaction == nil {
        if let occurrence, occurrence.isSkipped {
          Button("Restore Reminder", systemImage: "arrow.uturn.backward") {
            onRestore(occurrence)
          }
          .font(.subheadline)
        }
        if schedule.kind == .transfer && schedule.envelopeID == nil {
          Text("This transfer does not spend an envelope")
            .font(.caption).foregroundStyle(.secondary)
        } else if schedule.envelopeID == nil {
          Text("Choose an envelope to check funding")
            .font(.caption).foregroundStyle(.orange)
        } else if shortfall > 0 {
          Text("Envelope short by \(BudgetMoney.formatted(shortfall, currencyCode: currencyCode))")
            .font(.caption).foregroundStyle(.orange)
        }
        if selectedDate <= Date(), schedule.accountID != nil {
          Button(schedule.kind == .transfer ? "Record Transfer" : "Record Transaction", systemImage: "plus") {
            onRecord(ScheduledTransactionDraft(
              scheduleID: schedule.id, scheduledFor: selectedDate,
              accountID: schedule.accountID, transferAccountID: schedule.transferAccountID,
              envelopeID: schedule.envelopeID, kind: schedule.kind,
              amountMinor: schedule.amountMinor, payee: schedule.payee,
              notes: schedule.notes, date: selectedDate
            ))
          }
          .font(.subheadline)
        }
      } else if let recordedTransaction {
        Button("View Recorded Transaction", systemImage: "arrow.up.right") {
          onSelectTransaction(recordedTransaction.id)
        }
        .font(.subheadline)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 0.5) }
  }
}
