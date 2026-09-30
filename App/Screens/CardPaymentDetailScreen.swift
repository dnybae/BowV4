import SwiftUI
import SwiftData

struct CardPaymentDetailScreen: View {
  @Environment(\.modelContext) private var modelContext
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
                .monospacedDigit()
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

          HStack(spacing: Bow.Space.s3) {
            Button(owed > reserved ? "Fund payment" : "Move money", action: moveMoney)
              .bowPrimaryButton()
              .disabled(isPastMonth || snapshot.readyToAssignMinor <= 0 && reserved <= 0
                && !envelopes.contains { snapshot.available(for: $0.id) > 0 })
            Button("Payoff goal") { showingGoalEditor = true }
              .bowSecondaryButton()
              .disabled(isPastMonth)
          }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
      }

      if underfunded > 0 {
        Section("Underfunded") {
          LabeledContent("Total underfunded") {
            MoneyText(minor: underfunded, currencyCode: currencyCode)
              .fontWeight(.semibold).fontDesign(.rounded).monospacedDigit()
              .foregroundStyle(Bow.ink)
          }
          if overspentOnCard > 0 {
            VStack(alignment: .leading, spacing: Bow.Space.s2) {
              LabeledContent("Overspent envelopes") {
                MoneyText(minor: overspentOnCard, currencyCode: currencyCode)
                  .fontDesign(.rounded).monospacedDigit()
              }
              Text("Card purchases went over their envelopes. Covering them funds this payment.")
                .font(.footnote)
                .foregroundStyle(Bow.inkSoft)
              Button("Cover overspending", action: onCoverOverspending)
                .bowPrimaryButton(size: .regular)
                .disabled(isPastMonth)
            }
            .padding(.vertical, Bow.Space.s1)
          }
          if uncoveredDebt > 0 {
            VStack(alignment: .leading, spacing: Bow.Space.s2) {
              LabeledContent("Carried debt") {
                MoneyText(minor: uncoveredDebt, currencyCode: currencyCode)
                  .fontDesign(.rounded).monospacedDigit()
              }
              Text(hasPayoffGoal
                ? "Your payoff goal tracks this debt. Fund the payment a little each month."
                : "Debt from before this month. A payoff goal spreads it over time.")
                .font(.footnote)
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
        LabeledContent("Amount owed") {
          MoneyText(minor: owed, currencyCode: currencyCode)
            .fontDesign(.rounded).monospacedDigit()
        }
        ProgressView(value: debtProgress) {
          Text("Debt paid down")
        }
        .accessibilityValue("\(Int(debtProgress * 100)) percent")
        if let start = card.debtGoalStartMinor {
          Text(owed > start
            ? "Debt is \(BudgetMoney.formatted(owed - start, currencyCode: currencyCode)) above the goal’s starting balance."
            : "\(BudgetMoney.formatted(start - owed, currencyCode: currencyCode)) paid down from \(BudgetMoney.formatted(start, currencyCode: currencyCode))")
            .font(.footnote)
            .foregroundStyle(Bow.inkSoft)
        } else {
          Text("Set a payoff goal to track progress from today’s balance.")
            .font(.footnote)
            .foregroundStyle(Bow.inkSoft)
        }
        if let monthly = card.debtMonthlyTargetMinor {
          LabeledContent("Fund each month") {
            MoneyText(minor: monthly, currencyCode: currencyCode)
              .fontDesign(.rounded).monospacedDigit()
          }
        }
        if let date = card.debtGoalDate {
          LabeledContent("Target date", value: date.formatted(date: .abbreviated, time: .omitted))
        }
      }
      .listRowBackground(Bow.card)

      Section("Recurring transactions") {
        if cardSchedules.isEmpty {
          Text("No recurring transactions").foregroundStyle(Bow.inkSoft)
        } else {
          ForEach(cardSchedules) { schedule in
            Button { onEditSchedule(schedule.id) } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(schedule.payee)
                Text("\(schedule.frequency.title) · \(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))")
                  .font(.subheadline).foregroundStyle(Bow.inkSoft)
              }
            }
            .disabled(isPastMonth)
          }
        }
      }
      .listRowBackground(Bow.card)

      if feed.items.isEmpty && !feed.isLoading {
        Section("Card activity") {
          Text("No transactions yet").foregroundStyle(Bow.inkSoft)
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
              .buttonStyle(.plain)
              .disabled(isPastMonth)
            }
          }
          .listRowBackground(Bow.card)
        }
        if feed.hasMore {
          Section {
            ProgressView("Loading more…")
              .frame(maxWidth: .infinity)
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
                .fontDesign(.rounded).monospacedDigit()
            }
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: status.state.sky) }
    }
    .navigationTitle(card.name + " payment")
    .task(id: snapshot.month) {
      let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: snapshot.month) ?? .distantFuture
      await feed.reload(container: modelContext.container, searchText: "", filter: TransactionFilter(),
                        scopedAccountID: card.id, upperBound: nextMonth,
                        includeUncategorizedCount: false)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !isPastMonth { ToolbarItem(placement: .topBarTrailing) {
        Button("Edit Card", systemImage: "pencil") { showingAccountEditor = true }
      } }
    }
    .sheet(isPresented: $showingGoalEditor) {
      CardDebtGoalEditorScreen(card: card, currentDebtMinor: owed, currencyCode: currencyCode)
    }
    .sheet(isPresented: $showingAccountEditor) {
      AccountEditorScreen(currencyCode: currencyCode, account: card)
    }
  }
}
