import SwiftUI
import SwiftData

struct CardPaymentDetailScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  var card: BudgetAccount
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var previousSnapshot: BudgetSnapshot? = nil
  var isPastMonth: Bool = false
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var allocations: [BudgetAllocation]
  var schedules: [BudgetSchedule]
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onCoverOverspending: () -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var showingGoalEditor = false
  @State private var showingAccountEditor = false
  @State private var feed = TransactionFeedModel()
  @State private var hasLoadedFeed = false

  private var owed: Int64 { max(0, -snapshot.accountBalances[card.id, default: 0]) }
  private var reserved: Int64 { max(0, snapshot.paymentAvailable[card.id, default: 0]) }
  private var carriedDebt: Int64 {
    guard let previousSnapshot else { return 0 }
    let previousOwed = max(0, -previousSnapshot.accountBalances[card.id, default: 0])
    return max(0, previousOwed - max(0, previousSnapshot.paymentAvailable[card.id, default: 0]))
  }
  private var underfunded: Int64 { max(0, owed - reserved) }
  /// This month's credit overspending on this card. Covering those envelopes funds the payment.
  private var overspentOnCard: Int64 {
    min(underfunded, OverspendingSummary(snapshot: snapshot, envelopes: envelopes, groups: [], cardID: card.id)
      .creditMinor(onCard: card.id))
  }
  /// Debt that no overspent envelope explains, such as a starting balance or debt from earlier months.
  private var uncoveredDebt: Int64 { underfunded - overspentOnCard }
  private var hasPayoffGoal: Bool { card.debtMonthlyTargetMinor != nil || card.debtGoalDate != nil }
  private var baseline: Int64 { max(owed, card.debtGoalStartMinor ?? 0) }
  private var debtProgress: Double {
    guard baseline > 0 else { return 1 }
    return min(1, max(0, Double(baseline - owed) / Double(baseline)))
  }
  /// Opens Move Money into this card's payment from the most useful source, as before the redesign.
  private func moveMoney() {
    if snapshot.readyToAssignMinor > 0 {
      onMoveMoney(.readyToAssign, .cardPayment(card.id))
    } else if let funded = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      onMoveMoney(.envelope(funded.id), .cardPayment(card.id))
    } else {
      onMoveMoney(.cardPayment(card.id), .readyToAssign)
    }
  }

  private var canMoveMoney: Bool {
    !isPastMonth && (snapshot.readyToAssignMinor > 0 || reserved > 0
      || envelopes.contains { snapshot.available(for: $0.id) > 0 })
  }

  private var cardSchedules: [BudgetSchedule] {
    schedules.filter { $0.accountID == card.id }.sorted { $0.payee < $1.payee }
  }

  private var status: EnvelopeStatus {
    EnvelopeStatus(cardOwedMinor: owed, reservedMinor: reserved,
                   isCarryingDebt: carriedDebt > 0, currencyCode: currencyCode)
  }

  private var statusHeadline: (title: String, message: String)? {
    switch status.state {
    case .over:
      return (status.pillText, "to pay this card in full")
    case .needs:
      return (status.pillText, "to cover this month’s card spending")
    case .funded:
      return ("Ready to pay in full", "Payment money covers the full card balance.")
    case .empty:
      return nil
    }
  }

  var body: some View {
    List {
      Section {
        VStack(spacing: Bow.Space.s4) {
          GlowRing(fraction: status.ringFraction, color: status.state.ring, size: 200) {
            VStack(spacing: Bow.Space.s1) {
              Text("Payment ready")
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
              MoneyText(minor: reserved, currencyCode: currencyCode)
                .bowHeroFont()
                .foregroundStyle(Bow.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
              Text(owed > 0
                ? "of \(BudgetMoney.formatted(owed, currencyCode: currencyCode)) owed"
                : snapshot.month.formatted(.dateTime.month(.wide).year()))
                .font(.bowFootnote)
                .monospacedDigit()
                .foregroundStyle(Bow.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: 170)
          }
          .accessibilityElement(children: .combine)

          if let statusHeadline {
            VStack(spacing: 2) {
              Text(statusHeadline.title)
                .font(.bowTitle)
                .monospacedDigit()
                .foregroundStyle(Bow.ink)
              Text(statusHeadline.message)
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
          }

          BowStatStrip(stats: [
            .money("Owed", owed),
            .money("Set aside", reserved),
            .money("Carried debt", carriedDebt)
          ], currencyCode: currencyCode)

          BowActionTileRow {
            BowActionTile(owed > reserved ? "Fund" : "Move", systemImage: "plus",
                          isProminent: true, action: moveMoney)
              .disabled(!canMoveMoney)
            BowActionTile("Payoff goal", systemImage: "flag") { showingGoalEditor = true }
              .disabled(isPastMonth)
            BowActionTile("Edit card", systemImage: "pencil") { showingAccountEditor = true }
              .disabled(isPastMonth)
          }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
      }

      if underfunded > 0 {
        Section("Underfunded") {
          BowTileValueRow(title: "Total underfunded", systemImage: "exclamationmark.circle") {
            MoneyText(minor: underfunded, currencyCode: currencyCode)
              .fontWeight(.semibold)
              .foregroundStyle(Bow.ink)
          }
          if overspentOnCard > 0 {
            VStack(alignment: .leading, spacing: Bow.Space.s2) {
              BowTileValueRow(title: "Overspent envelopes", systemImage: "square.grid.2x2") {
                MoneyText(minor: overspentOnCard, currencyCode: currencyCode)
              }
              Text("Card purchases went over their envelopes. Covering them funds this payment.")
                .font(.bowFootnote)
                .foregroundStyle(Bow.inkSoft)
              Button("Cover overspending", action: onCoverOverspending)
                .bowPrimaryButton(size: .regular)
                .disabled(isPastMonth)
            }
            .padding(.vertical, Bow.Space.s1)
          }
          if uncoveredDebt > 0 {
            VStack(alignment: .leading, spacing: Bow.Space.s2) {
              BowTileValueRow(title: "Carried debt", systemImage: "clock.arrow.circlepath") {
                MoneyText(minor: uncoveredDebt, currencyCode: currencyCode)
              }
              Text(hasPayoffGoal
                ? "Your payoff goal tracks this debt. Fund the payment a little each month."
                : "Debt from before this month. A payoff goal spreads it over time.")
                .font(.bowFootnote)
                .foregroundStyle(Bow.inkSoft)
              if !hasPayoffGoal {
                Button("Set a payoff goal") { showingGoalEditor = true }
                  .bowSecondaryButton(size: .regular)
                  .disabled(isPastMonth)
              }
            }
            .padding(.vertical, Bow.Space.s1)
          }
        }
        .listRowBackground(Bow.card)
      }

      Section("Debt progress") {
        BowTileValueRow(title: "Amount owed", systemImage: "creditcard") {
          MoneyText(minor: owed, currencyCode: currencyCode)
        }
        ProgressView(value: debtProgress) {
          Text("Debt paid down")
        }
        .accessibilityValue("\(Int(debtProgress * 100)) percent")
        if let start = card.debtGoalStartMinor {
          Text(owed > start
            ? "Debt is \(BudgetMoney.formatted(owed - start, currencyCode: currencyCode)) above the goal’s starting balance."
            : "\(BudgetMoney.formatted(start - owed, currencyCode: currencyCode)) paid down from \(BudgetMoney.formatted(start, currencyCode: currencyCode))")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        } else {
          Text("Set a payoff goal to track progress from today’s balance.")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
        if let monthly = card.debtMonthlyTargetMinor {
          BowTileValueRow(title: "Fund each month", systemImage: "calendar.badge.clock") {
            MoneyText(minor: monthly, currencyCode: currencyCode)
          }
        }
        if let date = card.debtGoalDate {
          BowTileValueRow("Target date", systemImage: "flag",
                          value: date.formatted(date: .abbreviated, time: .omitted))
        }
      }
      .listRowBackground(Bow.card)

      Section("Recurring transactions") {
        if cardSchedules.isEmpty {
          Text("No recurring transactions").foregroundStyle(Bow.inkSoft)
        } else {
          ForEach(cardSchedules) { schedule in
            Button { onEditSchedule(schedule.id) } label: {
              ScheduleSummaryRow(schedule: schedule, currencyCode: currencyCode)
            }
            .disabled(isPastMonth)
          }
        }
      }
      .listRowBackground(Bow.card)

      if feed.items.isEmpty && (!hasLoadedFeed || feed.isLoading) {
        Section("Card activity") {
          BowTransactionSkeletonRows(count: 3)
        }
        .listRowBackground(Bow.card)
      } else if feed.items.isEmpty {
        Section("Card activity") {
          Text("Nothing charged to \(card.name) this month.").font(.bowBody).foregroundStyle(Bow.inkSoft)
        }
        .listRowBackground(Bow.card)
      } else {
        ForEach(TransactionDateGroup.make(feed.items)) { group in
          Section(group.title) {
            ForEach(group.items) { transaction in
              Button { onSelectTransaction(transaction.id) } label: {
                TransactionRowView(
                  model: TransactionRowModel(transaction),
                  currencyCode: currencyCode, options: .hidesAccount
                )
              }
            }
          }
          .listRowBackground(Bow.card)
        }
        if feed.hasMore {
          Section {
            BowTransactionSkeletonRows(count: 1)
              .onAppear { Task { await feed.loadNext() } }
          }
          .listRowBackground(Bow.card)
        }
      }

      let cardAllocations = allocations.filter {
        $0.sourceCardID == card.id || $0.targetCardID == card.id
      }.sorted { $0.date > $1.date }
      if !cardAllocations.isEmpty {
        Section("Payment money moves") {
          ForEach(cardAllocations) { allocation in
            LabeledContent(allocation.targetCardID == card.id ? "Moved in" : "Moved out") {
              MoneyText(minor: allocation.amountMinor, currencyCode: currencyCode)
            }
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: status.state.sky) }
    }
    .bowSoftScrollEdge()
    .bowAnimation(value: feed.items.map(\.id))
    .bowAnimation(value: hasLoadedFeed)
    .navigationTitle(card.name + " payment")
    .task(id: snapshot.month) {
      let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: snapshot.month) ?? .distantFuture
      await feed.reload(container: modelContext.container, searchText: "", filter: TransactionFilter(),
                        scopedAccountID: card.id, upperBound: nextMonth,
                        includeUncategorizedCount: false)
      hasLoadedFeed = true
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingGoalEditor) {
      CardDebtGoalEditorScreen(card: card, currentDebtMinor: owed, currencyCode: currencyCode)
    }
    .sheet(isPresented: $showingAccountEditor) {
      NavigationStack {
        AccountEditorScreen(currencyCode: currencyCode, account: card, onDeleted: { dismiss() })
      }
    }
  }
}
