import SwiftUI

struct CalendarScreen: View {
  var schedules: [BudgetSchedule]
  var transactions: [BudgetTransaction]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onRecord: (ScheduledTransactionDraft) -> Void
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

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
            .font(.system(size: 34, weight: .bold))
            .minimumScaleFactor(0.7)
          Spacer(minLength: 12)
          Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
            .labelStyle(.iconOnly)
          Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)

        let weekdaySymbols = calendar.veryShortStandaloneWeekdaySymbols
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { index in
            Text(weekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
        }
        .padding(.bottom, 6)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
          ForEach(days.indices, id: \.self) { index in
            if let day = days[index] {
              dayButton(day)
            } else {
              Color.clear.frame(height: 76)
                .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 0.5) }
            }
          }
        }

        VStack(alignment: .leading, spacing: 0) {
          HStack {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
              .font(.headline)
            Spacer()
            Text("\(selectedSchedules.count) scheduled")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)

          if selectedSchedules.isEmpty {
            ContentUnavailableView(
              "No scheduled bills",
              systemImage: "calendar.badge.clock",
              description: Text("Add a bill to see its upcoming dates and funding status.")
            )
            .frame(maxWidth: .infinity)
          } else {
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
      VStack(spacing: 7) {
        Text(day.formatted(.dateTime.day()))
          .font(.system(.title3, design: .rounded, weight: isSelected ? .bold : .medium))
          .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : (isToday ? Color.red : Color.primary))
          .frame(width: 34, height: 34)
          .background {
            if isSelected { Circle().fill(Color.primary) }
          }
        HStack(spacing: 3) {
          ForEach(due.prefix(3)) { schedule in
            Capsule()
              .fill(schedule.envelopeID == nil ? Color.orange : Color.accentColor)
              .frame(width: due.count == 1 ? 16 : 7, height: 5)
          }
        }
        .frame(height: 5)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 76)
      .contentShape(Rectangle())
      .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 0.5) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(due.count) scheduled bills")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func agendaRow(_ schedule: BudgetSchedule) -> some View {
    let recorded = transactions.contains {
      $0.scheduleID == schedule.id && $0.scheduledFor.map { calendar.isDate($0, inSameDayAs: selectedDate) } == true
    }
    let available = schedule.envelopeID.map { snapshot.available(for: $0) }
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
