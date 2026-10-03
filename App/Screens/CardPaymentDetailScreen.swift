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
  @Query(filter: #Predicate<BudgetScheduleOccurrence> { $0.isSkipped }) private var skippedOccurrences: [BudgetScheduleOccurrence]

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

  /// Each recurring bill's next date; past months have nothing upcoming.
  private var upcoming: [UpcomingSchedule] {
    guard !isPastMonth else { return [] }
    return UpcomingSchedules().items(for: cardSchedules, skipped: skippedOccurrences)
  }

  private var monthName: String { snapshot.month.formatted(.dateTime.month(.wide)) }

  private var moneyMoves: MoneyMoveHistory {
    MoneyMoveHistory(subject: .cardPayment(card.id), month: snapshot.month)
  }

  private var moneyMoveCount: Int { moneyMoves.count(allocations: allocations) }

  /// The debt a payoff goal spreads out: what was unfunded at the start of the month, or debt
  /// no overspent envelope explains, such as a starting balance added this month.
  private var payoffDebt: Int64 { max(carriedDebt, uncoveredDebt) }

  /// This month's amount toward the payoff goal. With a payoff date, Bow works it out.
  private var fundEachMonth: Int64? {
    CardPayoffPlanner().monthlyMinor(
      debtMinor: payoffDebt, monthlyTargetMinor: card.debtMonthlyTargetMinor,
      goalDate: card.debtGoalDate, month: snapshot.month
    )
  }

  private var payoffDetail: String? {
    if let date = card.debtGoalDate {
      return "To pay off by \(date.formatted(.dateTime.month(.wide).year()))"
    }
    guard let monthly = card.debtMonthlyTargetMinor,
          let month = CardPayoffPlanner().payoffMonth(debtMinor: payoffDebt, monthlyMinor: monthly, from: snapshot.month)
    else { return nil }
    return "Paid off around \(month.formatted(.dateTime.month(.wide).year()))"
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

      payoffSection

      if overspentOnCard > 0 {
        Section("Overspent on this card") {
          VStack(alignment: .leading, spacing: Bow.Space.s2) {
            EnvelopeDetailValueRow(title: "Overspent envelopes") {
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
        .listRowBackground(Bow.card)
      }

      Section {
        NavigationLink {
          MoneyMoveHistoryScreen(
            title: card.name + " payment", month: snapshot.month,
            entries: moneyMoves.moves(allocations: allocations, envelopes: envelopes, accounts: accounts),
            currencyCode: currencyCode
          )
        } label: {
          EnvelopeDetailValueRow(
            title: "Money moves", detail: "In \(monthName)",
            value: moneyMoveCount == 0 ? "None" : "\(moneyMoveCount)"
          )
        }
      }
      .listRowBackground(Bow.card)

      if !upcoming.isEmpty {
        Section("Upcoming") {
          ForEach(upcoming) { item in
            Button { onEditSchedule(item.scheduleID) } label: {
              TransactionRowView(
                model: item.rowModel(accountName: card.name, envelopeName: nil),
                currencyCode: currencyCode, options: .hidesAccount
              )
            }
          }
        }
        .listRowBackground(Bow.card)
      }

      if feed.items.isEmpty && (!hasLoadedFeed || feed.isLoading) {
        Section("Card activity") {
          BowTransactionSkeletonRows(count: 3)
        }
        .listRowBackground(Bow.card)
      } else if feed.items.isEmpty {
        Section("Card activity") {
          Text("Nothing charged to \(card.name) yet.").font(.bowBody).foregroundStyle(Bow.inkSoft)
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

    }
    .bowListBackground {
      Bow.mist
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
      CardDebtGoalEditorScreen(
        card: card, currentDebtMinor: owed, payoffDebtMinor: payoffDebt,
        month: snapshot.month, currencyCode: currencyCode
      )
    }
    .sheet(isPresented: $showingAccountEditor) {
      NavigationStack {
        AccountEditorScreen(currencyCode: currencyCode, account: card, onDeleted: { dismiss() })
      }
    }
  }

  /// Progress on the debt and what the payoff goal asks for this month. Rows open the goal.
  private var payoffSection: some View {
    Section("Payoff") {
      if hasPayoffGoal {
        if let start = card.debtGoalStartMinor {
          VStack(alignment: .leading, spacing: Bow.Space.s2) {
            ProgressView(value: debtProgress) {
              Text("Debt paid down")
                .font(.bowHeadline)
                .foregroundStyle(Bow.ink)
            }
            .accessibilityValue("\(Int(debtProgress * 100)) percent")
            Text(owed > start
              ? "\(BudgetMoney.formatted(owed - start, currencyCode: currencyCode)) above where the goal started"
              : "\(BudgetMoney.formatted(start - owed, currencyCode: currencyCode)) paid down from \(BudgetMoney.formatted(start, currencyCode: currencyCode))")
              .font(.bowSubhead)
              .monospacedDigit()
              .foregroundStyle(Bow.inkSoft)
          }
          .padding(.vertical, Bow.Space.s1)
        }
        payoffRow(title: "Fund each month", detail: payoffDetail) {
          if let fundEachMonth {
            MoneyText(minor: fundEachMonth, currencyCode: currencyCode)
          }
        }
      } else if owed > 0 {
        payoffRow(title: isPastMonth ? "No payoff goal" : "Set a payoff goal",
                  detail: "Pick a date and Bow works out the monthly amount") { EmptyView() }
      } else {
        EnvelopeDetailValueRow(title: "No debt on this card", detail: nil) { EmptyView() }
      }
    }
    .listRowBackground(Bow.card)
  }

  @ViewBuilder
  private func payoffRow<Value: View>(
    title: String, detail: String?, @ViewBuilder value: @escaping () -> Value
  ) -> some View {
    let row = EnvelopeDetailValueRow(title: title, detail: detail, value: value)
    if isPastMonth {
      row
    } else {
      Button { showingGoalEditor = true } label: { row }
    }
  }
}
