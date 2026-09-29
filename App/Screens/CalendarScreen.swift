import SwiftUI
import SwiftData

struct CalendarScreen: View {
  @Environment(\.modelContext) private var modelContext
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var transactions: [BudgetTransaction]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var currencyCode: String
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onSelectTransaction: (UUID) -> Void
  @State private var selectedDate = Date()
  @State private var visibleMonth = Date()
  @State private var editingSchedule: BudgetSchedule?

  private var calendar: Calendar { .current }
  private var selectedSchedules: [BudgetSchedule] {
    schedules.filter {
      $0.isActive && ScheduleRecurrence(calendar: calendar).occurs(
        starting: $0.startDate, frequency: $0.frequency, on: selectedDate
      )
    }.sorted { $0.payee < $1.payee }
  }
  private var dayTransactions: [BudgetTransaction] {
    transactions.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
      .sorted { $0.createdAt > $1.createdAt }
  }
  private var spentMinor: Int64 {
    let budgetAccountIDs = Set(accounts.filter { $0.kind == .cash || $0.kind == .credit }.map(\.id))
    return dayTransactions.reduce(0) { total, transaction in
      guard transaction.kind == .expense, transaction.amountMinor < 0,
            budgetAccountIDs.contains(transaction.accountID) else { return total }
      return total - transaction.amountMinor
    }
  }
  private var selectedSnapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: selectedDate, accounts: accounts, envelopes: envelopes,
      allocations: allocations, transactions: transactions
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      CalendarMonthPanel(
        visibleMonth: $visibleMonth, selectedDate: $selectedDate,
        schedules: schedules
      )
      Divider()
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

          if selectedSchedules.isEmpty && dayTransactions.isEmpty {
            ContentUnavailableView(
              "Nothing on this day",
              systemImage: "calendar",
              description: Text("Scheduled bills and recorded transactions will appear here.")
            )
            .frame(maxWidth: .infinity)
          }

          ForEach(selectedSchedules) { schedule in
            CalendarScheduleRow(
              schedule: schedule, selectedDate: selectedDate,
              occurrence: occurrences.first {
                $0.scheduleID == schedule.id
                  && calendar.isDate($0.scheduledFor, inSameDayAs: selectedDate)
              },
              transactions: transactions, snapshot: selectedSnapshot,
              currencyCode: currencyCode,
              onEdit: { editingSchedule = schedule },
              onRecord: onRecord,
              onRestore: { occurrence in
                occurrence.isSkipped = false
                try? modelContext.save()
              },
              onSelectTransaction: onSelectTransaction
            )
          }

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
        .padding(.bottom, 24)
      }
    }
    .navigationTitle("Calendar")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if !calendar.isDateInToday(selectedDate) {
          Button("Today") {
            withAnimation(.snappy) {
              selectedDate = Date()
              visibleMonth = Date()
            }
          }
        }
      }
    }
    .sheet(item: $editingSchedule) { schedule in
      ScheduleEditorScreen(schedule: schedule, accounts: accounts, envelopes: envelopes, currencyCode: currencyCode)
    }
  }
}

private struct CalendarMonthPanel: View {
  @Binding var visibleMonth: Date
  @Binding var selectedDate: Date
  var schedules: [BudgetSchedule]

  private var calendar: Calendar { .current }
  private var monthStart: Date { calendar.dateInterval(of: .month, for: visibleMonth)?.start ?? visibleMonth }
  private var days: [CalendarDayCell] {
    let firstWeekday = calendar.component(.weekday, from: monthStart)
    let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
    let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    let monthKey = monthStart.timeIntervalSince1970
    var result = (0..<leading).map { CalendarDayCell(id: "\(monthKey)-lead-\($0)", date: nil) }
    result += (0..<count).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: monthStart).map {
        CalendarDayCell(id: "\($0.timeIntervalSince1970)", date: $0)
      }
    }
    let trailing = (7 - result.count % 7) % 7
    result += (0..<trailing).map { CalendarDayCell(id: "\(monthKey)-trail-\($0)", date: nil) }
    return result
  }

  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
          .font(.title2.weight(.semibold))
          .minimumScaleFactor(0.75)
        Spacer()
        Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
        Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
      }
      HStack(spacing: 0) {
        ForEach(0..<7, id: \.self) { index in
          Text(calendar.veryShortStandaloneWeekdaySymbols[
            (calendar.firstWeekday - 1 + index) % 7
          ])
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 18)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
        ForEach(days) { cell in
          if let day = cell.date {
            dayButton(day)
          } else {
            Color.clear.frame(height: 42)
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 35).onEnded { value in
      guard abs(value.translation.height) > 60,
            abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
      shiftMonth(value.translation.height < 0 ? 1 : -1)
    })
  }

  private func dayButton(_ day: Date) -> some View {
    let dueCount = schedules.filter {
      $0.isActive && ScheduleRecurrence(calendar: calendar).occurs(
        starting: $0.startDate, frequency: $0.frequency, on: day
      )
    }.count
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
        Circle()
          .fill(dueCount > 0 ? Color.accentColor : Color.clear)
          .frame(width: 4, height: 4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(dueCount) scheduled bills")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func shiftMonth(_ offset: Int) {
    guard let next = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
    let dayNumber = calendar.component(.day, from: selectedDate)
    let last = calendar.range(of: .day, in: .month, for: next)?.count ?? 28
    let selected = calendar.date(byAdding: .day, value: min(dayNumber, last) - 1, to: next) ?? next
    withAnimation(.snappy) {
      visibleMonth = next
      selectedDate = selected
    }
  }
}

private struct CalendarDayCell: Identifiable {
  var id: String
  var date: Date?
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
