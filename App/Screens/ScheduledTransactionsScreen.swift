import SwiftUI
import SwiftData
import UIKit

struct ScheduledTransactionsScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  var schedules: [BudgetSchedule]
  var occurrences: [BudgetScheduleOccurrence]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  var onEditSchedule: (UUID) -> Void
  var onRecord: (ScheduledTransactionDraft) -> Void
  var onAddTransaction: () -> Void
  @State private var recorded: Set<ScheduleDateKey> = []
  @State private var hasLoaded = false
  @State private var refreshVersion = 0
  @State private var errorMessage: String?

  var body: some View {
    let items = ScheduleDirectory().items(schedules: schedules, occurrences: occurrences, recorded: recorded)
    List {
      if !hasLoaded {
        BowLoadingLabel("Loading scheduled transactions…")
          .frame(maxWidth: .infinity)
      } else if items.isEmpty {
        ContentUnavailableView {
          Label("No scheduled transactions", systemImage: "calendar.badge.clock")
        } description: {
          Text("Choose a future date when adding a transaction, or turn on Recurring for any date.")
        } actions: {
          Button("Add Transaction", systemImage: "plus", action: onAddTransaction)
            .bowPrimaryButton(size: .regular)
            .fixedSize()
        }
      } else {
        scheduleSection("Needs attention", items: items.filter(\.needsAttention))
        scheduleSection("Upcoming", items: items.filter { $0.schedule.isActive && !$0.needsAttention })
        scheduleSection("Paused", items: items.filter { !$0.schedule.isActive })
        Section {
          Text("Future transactions affect spending and balances when recorded. Each recurring transaction shows its next due date.")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
    }
    .bowListBackground()
    .bowSoftScrollEdge()
    .navigationTitle("Scheduled Transactions")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Transaction", systemImage: "plus", action: onAddTransaction)
          .labelStyle(.iconOnly)
      }
    }
    .task(id: refreshVersion) { loadRecordedDates() }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
      refreshVersion += 1
    }
    .bowErrorAlert("Scheduled Transactions", message: $errorMessage)
  }

  @ViewBuilder
  private func scheduleSection(_ title: String, items: [ScheduleDirectoryItem]) -> some View {
    if !items.isEmpty {
      Section(title) {
        ForEach(items) { item in
          Button { onEditSchedule(item.id) } label: {
            VStack(alignment: .leading, spacing: Bow.Space.s1) {
              HStack(spacing: Bow.Space.s2) {
                TransactionRowView(model: rowModel(for: item), currencyCode: currencyCode)
                Image(systemName: "chevron.right")
                  .font(.bowFootnote.weight(.semibold))
                  .foregroundStyle(Bow.inkFaint)
                  .accessibilityHidden(true)
              }
              Group {
                if item.schedule.isActive {
                  TransactionStatusLine(status: item.needsAttention ? .needsReview : .scheduled,
                                        text: item.statusLabel)
                } else {
                  Text(item.statusLabel)
                    .font(.bowFootnote)
                    .foregroundStyle(Bow.inkSoft)
                }
              }
              .padding(.leading, 40 + Bow.Space.s3)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Bow.Space.s1)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(rowModel(for: item).title)
          .accessibilityValue([
            BudgetMoney.formatted(rowModel(for: item).amountMinor, currencyCode: currencyCode,
                                  showsPlusSign: item.schedule.kind == .inflow),
            rowModel(for: item).subtitle(hiding: []) ?? "", item.statusLabel
          ].joined(separator: ", "))
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.schedule.isActive, item.schedule.frequency != .once {
              Button("Pause", systemImage: "pause") { setActive(false, for: item.schedule) }
                .tint(Bow.inkSoft)
            } else if !item.schedule.isActive {
              Button("Resume", systemImage: "play") { setActive(true, for: item.schedule) }
                .tint(Bow.fundedInk)
            }
            if item.schedule.isActive, item.date != nil, item.schedule.frequency != .once {
              Button("Skip next", systemImage: "forward.end") { skip(item) }
                .tint(Bow.inkSoft)
            }
          }
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if item.needsAttention, let date = item.date {
              Button("Enter now", systemImage: "plus") {
                let schedule = item.schedule
                onRecord(ScheduledTransactionDraft(
                  scheduleID: schedule.id, scheduledFor: date, accountID: schedule.accountID,
                  transferAccountID: schedule.transferAccountID, envelopeID: schedule.envelopeID,
                  kind: schedule.kind, amountMinor: schedule.amountMinor, payee: schedule.payee, date: date
                ))
              }
              .tint(Bow.fundedInk)
            }
          }
        }
      }
      .listRowBackground(Bow.card)
    }
  }

  private func rowModel(for item: ScheduleDirectoryItem) -> TransactionRowModel {
    let schedule = item.schedule
    return TransactionRowModel(
      id: item.id.uuidString,
      title: TransactionRowModel.title(payee: schedule.payee, kind: schedule.kind),
      logoName: schedule.kind == .transfer ? "" : schedule.payee,
      merchantDomain: nil, kind: schedule.kind,
      accountName: accounts.first { $0.id == schedule.accountID }?.name ?? "Choose an account",
      envelopeName: envelopes.first { $0.id == schedule.envelopeID }?.name,
      amountMinor: schedule.kind == .inflow ? abs(schedule.amountMinor) : -abs(schedule.amountMinor),
      state: .normal
    )
  }

  private func loadRecordedDates() {
    do {
      recorded = try ScheduleDirectory().recordedDates(in: modelContext)
      hasLoaded = true
    } catch { errorMessage = error.localizedDescription }
  }

  private func setActive(_ active: Bool, for schedule: BudgetSchedule) {
    do {
      try ScheduleManagement.setActive(active, for: schedule, in: modelContext)
      toasts?.show(.saved("\(active ? "Resumed" : "Paused") · \(schedule.payee)"))
    } catch { errorMessage = error.localizedDescription }
  }

  private func skip(_ item: ScheduleDirectoryItem) {
    guard let date = item.date else { return }
    do {
      let undo = try UndoableChanges.skip(scheduleID: item.id, date: date, in: modelContext)
      try? ScheduleTargetSynchronizer().refresh(in: modelContext)
      toasts?.show(.deleted("Skipped · \(item.schedule.payee)", undo: undo))
    } catch { errorMessage = error.localizedDescription }
  }
}
