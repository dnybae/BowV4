import SwiftUI

struct CalendarScreen: View {
  var schedules: [BudgetSchedule]
  var transactions: [BudgetTransaction]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var currencyCode: String
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onSelectTransaction: (UUID) -> Void
  @State private var selectedDate = Date()
  @State private var visibleMonth = Date()
  @State private var showingNewSchedule = false
  @State private var editingSchedule: BudgetSchedule?

  private var calendar: Calendar { .current }
  private var monthStart: Date {
    calendar.dateInterval(of: .month, for: visibleMonth)?.start ?? visibleMonth
  }
  private var days: [Date?] {
    let firstWeekday = calendar.component(.weekday, from: monthStart)
    let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
    let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    let dates: [Date?] = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: monthStart) }
    let all = Array<Date?>(repeating: nil, count: leading) + dates
    return all + Array<Date?>(repeating: nil, count: (7 - all.count % 7) % 7)
  }
  private var selectedSchedules: [BudgetSchedule] {
    schedulesForDay(selectedDate)
  }
  private var selectedSnapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: selectedDate,
      accounts: accounts,
      envelopes: envelopes,
      allocations: allocations,
      transactions: transactions
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
            .font(.title2.weight(.bold))
            .minimumScaleFactor(0.7)
          Spacer(minLength: 12)
          Button { shiftMonth(-1) } label: {
            Label("Previous Month", systemImage: "chevron.left")
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          Button { shiftMonth(1) } label: {
            Label("Next Month", systemImage: "chevron.right")
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
        }
        .padding(.horizontal, 20)

        let weekdaySymbols = calendar.veryShortStandaloneWeekdaySymbols
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { index in
            Text(weekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 18)
        .padding(.bottom, 2)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
          ForEach(days.indices, id: \.self) { index in
            if let day = days[index] {
              dayButton(day)
            } else {
              Color.clear.frame(height: 48)
            }
          }
        }
        .padding(.bottom, 8)

        HStack {
          Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(.headline)
          Spacer()
          Text("\(selectedSchedules.count) scheduled")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 0.5) }

        if selectedSchedules.isEmpty {
          ContentUnavailableView(
            "No scheduled bills",
            systemImage: "calendar.badge.clock",
            description: Text("Add a bill to see its upcoming dates and funding status.")
          )
          .frame(maxWidth: .infinity)
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(selectedSchedules) { schedule in
              agendaRow(schedule)
            }
          }
        }
      }
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Calendar")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Scheduled Bill", systemImage: "plus") { showingNewSchedule = true }
      }
    }
    .sheet(isPresented: $showingNewSchedule) {
      ScheduleEditorScreen(schedule: nil, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
    }
    .sheet(item: $editingSchedule) { schedule in
      ScheduleEditorScreen(schedule: schedule, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
    }
  }

  private func dayButton(_ day: Date) -> some View {
    let due = schedulesForDay(day)
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDateInToday(day)
    return Button {
      selectedDate = day
    } label: {
      VStack(spacing: 2) {
        Text(day.formatted(.dateTime.day()))
          .font(.system(.callout, design: .rounded, weight: isSelected ? .bold : .medium))
          .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : (isToday ? Color.red : Color.primary))
          .frame(width: 28, height: 28)
          .background {
            if isSelected { Circle().fill(Color.primary) }
          }
        HStack(spacing: 3) {
          ForEach(due.prefix(3)) { schedule in
            Capsule()
              .fill(schedule.envelopeID == nil ? Color.orange : Color.accentColor)
              .frame(width: due.count == 1 ? 14 : 6, height: 4)
          }
        }
        .frame(height: 4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(due.count) scheduled bills")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func agendaRow(_ schedule: BudgetSchedule) -> some View {
    let recordedTransaction = transactions.first {
      $0.scheduleID == schedule.id && $0.scheduledFor.map { calendar.isDate($0, inSameDayAs: selectedDate) } == true
    }
    let recorded = recordedTransaction != nil
    let available = schedule.envelopeID.map { selectedSnapshot.available(for: $0) }
    let shortfall = max(0, schedule.amountMinor - max(0, available ?? 0))
    return VStack(alignment: .leading, spacing: 8) {
      Button { editingSchedule = schedule } label: {
        HStack(alignment: .top, spacing: 10) {
          RoundedRectangle(cornerRadius: 2)
            .fill(schedule.envelopeID == nil ? .orange : Color.accentColor)
            .frame(width: 4)
          VStack(alignment: .leading, spacing: 4) {
            Text(schedule.payee).font(.headline)
            Text(schedule.frequency.title + (recorded ? " · Recorded" : " · Expected"))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))
            .font(.subheadline.weight(.semibold))
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if !recorded, schedule.envelopeID == nil {
        Label("Choose an envelope to check funding", systemImage: "tag")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if !recorded, shortfall > 0 {
        Label("Envelope short by \(BudgetMoney.formatted(shortfall, currencyCode: currencyCode))", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      if !recorded, selectedDate <= Date(), schedule.accountID != nil {
        Button("Record Payment", systemImage: "plus") {
          onRecord(ScheduledTransactionDraft(
            scheduleID: schedule.id,
            scheduledFor: selectedDate,
            accountID: schedule.accountID,
            envelopeID: schedule.envelopeID,
            amountMinor: schedule.amountMinor,
            payee: schedule.payee,
            notes: schedule.notes,
            date: selectedDate
          ))
        }
        .font(.subheadline)
      }
      if let recordedTransaction {
        Button("View Recorded Transaction", systemImage: "arrow.up.right") {
          onSelectTransaction(recordedTransaction.id)
        }
        .font(.subheadline)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 0.5) }
  }

  private func schedulesForDay(_ date: Date) -> [BudgetSchedule] {
    schedules.filter { $0.isActive && ScheduleRecurrence(calendar: calendar).occurs(starting: $0.startDate, frequency: $0.frequency, on: date) }
      .sorted { $0.payee.localizedCaseInsensitiveCompare($1.payee) == .orderedAscending }
  }

  private func shiftMonth(_ offset: Int) {
    guard let next = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
    visibleMonth = next
    selectedDate = next
  }
}
