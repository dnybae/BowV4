import SwiftUI
import SwiftData

struct CalendarScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  @Binding var selectedDate: Date
  var returnToTodayRequest: Int = 0
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onSelectTransaction: (UUID) -> Void
  @State private var months = CalendarTimelineWindow.months(around: Date())
  @State private var scrollMonth: Date?
  @State private var editingSchedule: BudgetSchedule?
  @State private var monthTransactions: [BudgetTransaction] = []
  @State private var selectedSnapshot: BudgetSnapshot?
  @State private var snapshotRepository: BudgetSnapshotRepository?
  @State private var refreshVersion = 0
  @State private var isLoadingMonth = false

  private var calendar: Calendar { .current }
  private var currentMonth: Date {
    calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
  }
  private var visibleMonth: Date { scrollMonth ?? currentMonth }
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
        weekdayHeader
        Divider()
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(months, id: \.self) { month in
              CalendarTimelineMonth(
                month: month, selectedDate: $selectedDate,
                schedules: schedules
              )
              .id(month)
            }
          }
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollMonth, anchor: .top)
        .onAppear {
          let target = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? currentMonth
          if !months.contains(target) { months = CalendarTimelineWindow.months(around: target) }
          Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(target, anchor: .top)
          }
        }
        .onChange(of: scrollMonth) { _, month in
          guard let month else { return }
          CalendarTimelineWindow.extend(&months, near: month, calendar: calendar)
        }
        Divider()
        selectedDayAgenda
          .frame(height: 230)
      }
      .navigationTitle("Calendar")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if !calendar.isDateInToday(selectedDate) || visibleMonth != currentMonth {
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
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        refreshVersion += 1
      }
      .sheet(item: $editingSchedule) { schedule in
        ScheduleEditorScreen(schedule: schedule, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
      }
    }
  }

  private var weekdayHeader: some View {
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

  private func returnToToday(using proxy: ScrollViewProxy) {
    let today = Date()
    let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    selectedDate = today
    if !months.contains(month) {
      months = CalendarTimelineWindow.months(around: month)
      scrollMonth = month
      Task { @MainActor in
        await Task.yield()
        proxy.scrollTo(month, anchor: .top)
      }
    } else {
      withAnimation(reduceMotion ? nil : .snappy) {
        scrollMonth = month
        proxy.scrollTo(month, anchor: .top)
      }
    }
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

private struct CalendarTimelineMonth: View {
  @Environment(\.modelContext) private var modelContext
  var month: Date
  @Binding var selectedDate: Date
  var schedules: [BudgetSchedule]
  @State private var transactionDays: Set<Date> = []

  private var calendar: Calendar { .current }
  private var days: [CalendarDayCell] {
    let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
    let key = month.timeIntervalSince1970
    var result = (0..<leading).map { CalendarDayCell(id: "\(key)-lead-\($0)", date: nil) }
    result += (0..<count).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: month).map {
        CalendarDayCell(id: "\($0.timeIntervalSince1970)", date: $0)
      }
    }
    result += (0..<(7 - result.count % 7) % 7)
      .map { CalendarDayCell(id: "\(key)-trail-\($0)", date: nil) }
    return result
  }
  private var scheduleCounts: [Date: Int] {
    let recurrence = ScheduleRecurrence(calendar: calendar)
    var counts: [Date: Int] = [:]
    for day in days.compactMap(\.date) {
      counts[day] = schedules.reduce(0) { count, schedule in
        count + (schedule.isActive && recurrence.occurs(
          starting: schedule.startDate, frequency: schedule.frequency, on: day
        ) ? 1 : 0)
      }
    }
    return counts
  }
  var body: some View {
    let counts = scheduleCounts
    let recorded = transactionDays
    VStack(alignment: .leading, spacing: 8) {
      Text(month.formatted(.dateTime.month(.wide).year()))
        .font(.title2.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
        ForEach(days) { cell in
          if let day = cell.date {
            dayButton(day, scheduled: counts[day, default: 0], recorded: recorded.contains(day))
          } else {
            Color.clear.frame(height: 44)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: month) {
      let next = calendar.date(byAdding: .month, value: 1, to: month) ?? .distantFuture
      let predicate = #Predicate<BudgetTransaction> { $0.date >= month && $0.date < next }
      var descriptor = FetchDescriptor<BudgetTransaction>(predicate: predicate)
      descriptor.propertiesToFetch = [\.date]
      let dates = (try? modelContext.fetch(descriptor))?.map(\.date) ?? []
      transactionDays = Set(dates.map { calendar.startOfDay(for: $0) })
    }
  }

  private func dayButton(_ day: Date, scheduled: Int, recorded: Bool) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    return Button {
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
          .fill(scheduled > 0 || recorded ? Color.accentColor : Color.clear)
          .frame(width: 5, height: 5)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(scheduled) scheduled bills\(recorded ? ", recorded transactions" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct CalendarDayCell: Identifiable {
  var id: String
  var date: Date?
}

private enum CalendarTimelineWindow {
  static func months(around date: Date, calendar: Calendar = .current) -> [Date] {
    let center = calendar.dateInterval(of: .month, for: date)?.start ?? date
    return (-6...6).compactMap { calendar.date(byAdding: .month, value: $0, to: center) }
  }

  static func extend(_ months: inout [Date], near visible: Date, calendar: Calendar) {
    guard let index = months.firstIndex(of: visible), !months.isEmpty else { return }
    if index <= 2, let first = months.first {
      let earlier = (1...6).reversed().compactMap {
        calendar.date(byAdding: .month, value: -$0, to: first)
      }
      months.insert(contentsOf: earlier, at: 0)
      if months.count > 31 { months.removeLast(min(earlier.count, months.count - 31)) }
    } else if index >= months.count - 3, let last = months.last {
      let later = (1...6).compactMap { calendar.date(byAdding: .month, value: $0, to: last) }
      months.append(contentsOf: later)
      if months.count > 31 { months.removeFirst(min(later.count, months.count - 31)) }
    }
  }
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
