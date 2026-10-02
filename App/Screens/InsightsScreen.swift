import SwiftUI
import Charts
import SwiftData

struct InsightsScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var currentNetWorth: AccountBalanceReport
  var snapshotRepository: BudgetSnapshotRepository
  var schedules: [BudgetSchedule] = []
  var currencyCode: String
  @State private var selectedBarMonth: Date?
  @State private var selectedSpendingAngle: Double?
  /// The month and group last scrubbed to; they stay highlighted after the finger lifts.
  @State private var pinnedBarMonth: Date?
  @State private var pinnedGroupID: UUID?
  @State private var detail: InsightsDetail?
  @State private var editingTransaction: BudgetTransaction?
  @State private var transactions: [BudgetTransaction] = []
  @State private var monthlyNetWorth: [Date: Int64] = [:]
  @State private var refreshVersion = 0
  @State private var hasLoaded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var calendar: Calendar { .current }
  private var months: [Date] {
    let current = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    return (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
  }
  private var accountKinds: [UUID: BudgetAccountKind] {
    Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.kind) })
  }
  private var netWorthIssueDescription: String {
    guard let issue = currentNetWorth.issues.first else { return "Review your account balances." }
    switch issue {
    case .currencyMismatch(let id):
      let name = accounts.first { $0.id == id }?.name ?? "An account"
      return "\(name) uses a different currency from this budget."
    case .mixedCurrencies:
      return "Accounts use different currencies. Conversion rates are needed before they can be totaled."
    case .missingAccount:
      return "A recorded transaction references an account that is no longer available."
    case .positiveLiability(let id):
      let name = accounts.first { $0.id == id }?.name ?? "A loan"
      return "\(name) has a positive balance. Enter money owed as a negative amount."
    case .overflow:
      return "One or more balances are too large to total safely."
    }
  }
  private var forecast: [BowForecastMonth] {
    guard let current = currentNetWorth.netWorthMinor else { return [] }
    return BowForecast().project(from: Date(), currentNetWorthMinor: current,
                                 transactions: transactions, schedules: schedules)
  }
  private var monthItems: [InsightsMonth] {
    months.map { month in
      let items = transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
      let income = items.filter {
        $0.kind == .inflow && !$0.isBalanceAdjustment && accountKinds[$0.accountID] == .cash
      }
        .reduce(Int64(0)) { $0 + max(0, $1.amountMinor) }
      let expenses = items.filter { transaction in
        (transaction.kind == .expense && !transaction.isBalanceAdjustment
          && [.cash, .credit].contains(accountKinds[transaction.accountID]))
          || (transaction.kind == .transfer
          && accountKinds[transaction.accountID] == .cash
          && [.asset, .liability].contains(accountKinds[transaction.transferAccountID ?? UUID()]))
      }.reduce(Int64(0)) { $0 + max(0, -$1.amountMinor) }
      let isCurrent = calendar.isDate(month, equalTo: Date(), toGranularity: .month)
      let netWorth = isCurrent ? currentNetWorth.netWorthMinor : monthlyNetWorth[month]
      return InsightsMonth(month: month, incomeMinor: income, expenseMinor: expenses, netWorthMinor: netWorth)
    }
  }
  private var spendingGroups: [InsightsGroup] {
    let envelopeGroups = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, $0.groupID) })
    let thisMonth = months.last ?? Date()
    let spent = transactions.filter {
      calendar.isDate($0.date, equalTo: thisMonth, toGranularity: .month)
        && $0.amountMinor < 0 && $0.envelopeID != nil
        && ($0.kind == .expense || $0.kind == .transfer)
    }
    return groups.compactMap { group in
      let matching = spent.filter { envelopeGroups[$0.envelopeID ?? UUID()] == group.id }
      let total = matching.reduce(Int64(0)) { $0 - $1.amountMinor }
      return total > 0 ? InsightsGroup(id: group.id, name: group.name, totalMinor: total, transactions: matching) : nil
    }.sorted { $0.totalMinor > $1.totalMinor }
  }

  /// "The Arrow": recent net worth flowing into the six-month estimate, drawn on a sky card.
  private var arrowCard: some View {
    let past = monthItems.suffix(3).compactMap { item in item.netWorthMinor.map { (item.month, $0) } }
    let today = past.last
    let projection = (today.map { [$0] } ?? []) + forecast.map { ($0.month, $0.netWorthMinor) }
    return VStack(alignment: .leading, spacing: Bow.Space.s3) {
      Label("The Arrow", systemImage: "chart.line.uptrend.xyaxis")
        .font(.bowSubhead.weight(.semibold))
        .foregroundStyle(Bow.bowInk)
      Text("Where your net worth is headed")
        .font(.bowTitle)
        .foregroundStyle(Bow.ink)
      Chart {
        ForEach(past, id: \.0) { month, value in
          LineMark(x: .value("Month", month, unit: .month), y: .value("Net Worth", Double(value) / 100),
                   series: .value("Series", "Past"))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(Bow.bow.opacity(0.45))
        }
        ForEach(projection, id: \.0) { month, value in
          LineMark(x: .value("Month", month, unit: .month), y: .value("Net Worth", Double(value) / 100),
                   series: .value("Series", "Projected"))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
            .foregroundStyle(LinearGradient(colors: [Bow.bow.opacity(0.6), Bow.bow], startPoint: .leading, endPoint: .trailing))
        }
        if let today {
          PointMark(x: .value("Month", today.0, unit: .month), y: .value("Net Worth", Double(today.1) / 100))
            .symbolSize(120)
            .foregroundStyle(Bow.bow)
            .annotation(position: .bottom, alignment: .center, spacing: 6) {
              VStack(spacing: 0) {
                Text("Today").font(.bowFootnote).foregroundStyle(Bow.inkSoft)
                MoneyText(minor: today.1, currencyCode: currencyCode)
                  .font(.bowAmountSm).monospacedDigit().foregroundStyle(Bow.ink)
              }
            }
        }
        if let last = forecast.last {
          PointMark(x: .value("Month", last.month, unit: .month), y: .value("Net Worth", Double(last.netWorthMinor) / 100))
            .symbol {
              Image(systemName: "arrowtriangle.right.fill")
                .font(.bowCaption)
                .foregroundStyle(Bow.bow)
            }
            .annotation(position: .bottom, alignment: .trailing, spacing: 10) {
              VStack(alignment: .trailing, spacing: 0) {
                Text(last.month.formatted(.dateTime.month(.wide).year()))
                  .font(.bowFootnote).foregroundStyle(Bow.inkSoft)
                MoneyText(minor: last.netWorthMinor, currencyCode: currencyCode)
                  .font(.bowTitle).monospacedDigit().foregroundStyle(Bow.bowInk)
              }
            }
        }
      }
      .chartYAxis(.hidden)
      .chartXAxis(.hidden)
      .chartYScale(domain: .automatic(includesZero: false))
      .frame(height: 210)
      .padding(.vertical, Bow.Space.s4)
      .shadow(color: Bow.bow.opacity(0.35), radius: 8)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Net worth forecast")
      .accessibilityValue(forecast.last.map {
        "Projected \(BudgetMoney.formatted($0.netWorthMinor, currencyCode: currencyCode)) by \($0.month.formatted(.dateTime.month(.wide).year()))"
      } ?? "Not enough data yet")
      Text("Estimate from recent income, spending and schedules. Transfers between your own accounts don’t change net worth.")
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
    }
    .padding(Bow.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      ZStack {
        Bow.card
        LinearGradient(colors: [SkyMood.dawn.top, Bow.card.opacity(0)], startPoint: .top, endPoint: .bottom)
        RadialGradient(colors: [SkyMood.dawn.warm.opacity(0.8), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Bow.Radius.xl, style: .continuous))
    .shadow(color: .black.opacity(0.05), radius: 10, y: 6)
  }

  private var selectedItem: InsightsMonth? {
    let month = selectedBarMonth ?? pinnedBarMonth
    return month.flatMap { month in
      monthItems.first { calendar.isDate($0.month, equalTo: month, toGranularity: .month) }
    }
  }

  private func barOpacity(for month: Date) -> Double {
    guard let selectedItem else { return 1 }
    return calendar.isDate(selectedItem.month, equalTo: month, toGranularity: .month) ? 1 : 0.4
  }

  /// The scrubbed month's totals and a button to open its transactions.
  @ViewBuilder
  private var monthSelectionFooter: some View {
    if let item = selectedItem {
      HStack(alignment: .firstTextBaseline, spacing: Bow.Space.s3) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.month.formatted(.dateTime.month(.wide).year()))
            .font(.bowSubhead.weight(.semibold))
            .foregroundStyle(Bow.ink)
          HStack(spacing: Bow.Space.s1) {
            Text("In")
            MoneyText(minor: item.incomeMinor, currencyCode: currencyCode)
            Text("· Out")
            MoneyText(minor: item.expenseMinor, currencyCode: currencyCode)
          }
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
        }
        Spacer(minLength: Bow.Space.s2)
        Button("See transactions") {
          let matching = transactions.filter { calendar.isDate($0.date, equalTo: item.month, toGranularity: .month) }
          detail = InsightsDetail(title: item.month.formatted(.dateTime.month(.wide).year()), transactions: matching)
        }
        .bowSecondaryButton(size: .small)
      }
      .accessibilityElement(children: .combine)
      .transition(.opacity)
    } else {
      Text("Drag across the chart to compare months.")
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
        .transition(.opacity)
    }
  }

  private var selectedGroup: InsightsGroup? {
    if let selectedSpendingAngle { return group(atAngle: selectedSpendingAngle) }
    return spendingGroups.first { $0.id == pinnedGroupID }
  }

  private func group(atAngle value: Double) -> InsightsGroup? {
    var boundary = 0.0
    for group in spendingGroups {
      boundary += Double(group.totalMinor)
      if value <= boundary { return group }
    }
    return nil
  }

  /// The donut's middle: the touched group, or this month's total.
  private var donutCenter: some View {
    VStack(spacing: 2) {
      Text(selectedGroup?.name ?? "Spent")
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
        .lineLimit(1)
      MoneyText(minor: selectedGroup?.totalMinor ?? spendingGroups.reduce(0) { $0 + $1.totalMinor },
                currencyCode: currencyCode)
        .font(.bowAmount)
        .foregroundStyle(Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .multilineTextAlignment(.center)
  }

  /// Calm categorical colors for envelope groups. Coral is left out because it means overspent.
  private static let groupPalette: [Color] = [
    Bow.bow, Bow.funded, Bow.needs, Bow.bowInk, Bow.fundedInk, Bow.needsInk, Bow.inkSoft
  ]

  private var currencyAxis: some AxisContent {
    AxisMarks { _ in
      AxisGridLine()
      AxisValueLabel(format: .currency(code: currencyCode).precision(.fractionLength(0)))
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Bow.Space.s4) {
        arrowCard

        VStack(alignment: .leading, spacing: Bow.Space.s3) {
          Text("Income and spending").font(.bowHeadline).foregroundStyle(Bow.ink)
          Chart {
            ForEach(monthItems) { item in
              BarMark(x: .value("Month", item.month, unit: .month), y: .value("Amount", Double(item.incomeMinor) / 100))
                .foregroundStyle(by: .value("Flow", "Income"))
                .position(by: .value("Flow", "Income"))
                .clipShape(Capsule())
                .opacity(barOpacity(for: item.month))
              BarMark(x: .value("Month", item.month, unit: .month), y: .value("Amount", Double(item.expenseMinor) / 100))
                .foregroundStyle(by: .value("Flow", "Spending"))
                .position(by: .value("Flow", "Spending"))
                .clipShape(Capsule())
                .opacity(barOpacity(for: item.month))
            }
            if let selectedItem {
              RuleMark(x: .value("Month", selectedItem.month, unit: .month))
                .foregroundStyle(Bow.line)
                .zIndex(-1)
            }
          }
          .chartForegroundStyleScale(["Income": Bow.funded, "Spending": Bow.bow])
          .chartXSelection(value: $selectedBarMonth)
          .frame(height: 220)
          .chartYAxis { currencyAxis }
          .redacted(reason: hasLoaded ? [] : .placeholder)
          .sensoryFeedback(.selection, trigger: selectedItem?.month)
          monthSelectionFooter
        }
        .insightCard()
        .bowAnimation(value: pinnedBarMonth)

        VStack(alignment: .leading, spacing: Bow.Space.s3) {
          Text("Spending by group").font(.bowHeadline).foregroundStyle(Bow.ink)
          Text((months.last ?? Date()).formatted(.dateTime.month(.wide).year()))
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
          if !hasLoaded {
            Circle()
              .stroke(Bow.well, lineWidth: 28)
              .frame(height: 182)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Bow.Space.s3)
              .bowShimmer()
              .accessibilityHidden(true)
          } else if spendingGroups.isEmpty {
            ContentUnavailableView("No spending yet", systemImage: "chart.pie", description: Text("Expenses with an envelope will appear here."))
          } else {
            Chart(spendingGroups) { group in
              SectorMark(angle: .value("Spending", Double(group.totalMinor)), innerRadius: .ratio(0.65), angularInset: 2)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Group", group.name))
                .opacity(selectedGroup == nil || selectedGroup?.id == group.id ? 1 : 0.35)
            }
            .chartForegroundStyleScale(domain: spendingGroups.map(\.name), range: Self.groupPalette)
            .chartAngleSelection(value: $selectedSpendingAngle)
            .chartBackground { proxy in
              GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                  let rect = geometry[frame]
                  donutCenter
                    .frame(width: rect.width * 0.55)
                    .position(x: rect.midX, y: rect.midY)
                }
              }
            }
            .frame(height: 210)
            .sensoryFeedback(.selection, trigger: selectedGroup?.id)
            .accessibilityLabel("Spending by envelope group")
            ForEach(spendingGroups) { group in
              Button {
                detail = InsightsDetail(title: group.name, transactions: group.transactions)
              } label: {
                HStack {
                  Text(group.name)
                    .font(.bowHeadline)
                    .foregroundStyle(Bow.ink)
                  Spacer()
                  MoneyText(minor: group.totalMinor, currencyCode: currencyCode)
                    .font(.bowAmountSm)
                    .foregroundStyle(Bow.ink)
                  Image(systemName: "chevron.right")
                    .font(.bowFootnote.weight(.semibold))
                    .foregroundStyle(Bow.inkFaint)
                    .accessibilityHidden(true)
                }
                .padding(.vertical, Bow.Space.s2)
                .padding(.horizontal, Bow.Space.s2)
                .contentShape(Rectangle())
              }
              .buttonStyle(.bowRowPress)
              .clipShape(RoundedRectangle(cornerRadius: Bow.Radius.sm, style: .continuous))
              .padding(.horizontal, -Bow.Space.s2)
            }
          }
        }
        .insightCard()

        VStack(alignment: .leading, spacing: Bow.Space.s3) {
          Text("Net worth").font(.bowHeadline).foregroundStyle(Bow.ink)
          if let value = currentNetWorth.netWorthMinor {
            MoneyText(minor: value, currencyCode: currencyCode)
              .font(.bowTitle)
              .monospacedDigit()
              .foregroundStyle(Bow.ink)
              .accessibilityLabel("Current net worth, \(BudgetMoney.formatted(value, currencyCode: currencyCode))")
          } else {
            Text("Net worth unavailable")
              .font(.bowSubhead.weight(.semibold))
            Text(netWorthIssueDescription)
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
          }
          Chart(monthItems) { item in
            if let value = item.netWorthMinor {
              LineMark(x: .value("Month", item.month, unit: .month), y: .value("Net Worth", Double(value) / 100))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(Bow.bow)
              PointMark(x: .value("Month", item.month, unit: .month), y: .value("Net Worth", Double(value) / 100))
                .foregroundStyle(Bow.bow)
            }
          }
          .frame(height: 190)
          .chartYAxis { currencyAxis }
          .redacted(reason: hasLoaded ? [] : .placeholder)
          Text("Includes tracking accounts and credit balances.")
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
        .insightCard()
      }
      .padding(.horizontal, Bow.Space.s5)
      .padding(.top, Bow.Space.s4)
      .padding(.bottom, Bow.Space.s6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .bowSoftScrollEdge()
    .task(id: refreshVersion) {
      let first = months.first ?? Date()
      let next = Calendar.current.date(byAdding: .month, value: 1, to: months.last ?? Date()) ?? Date()
      let predicate = #Predicate<BudgetTransaction> { $0.date >= first && $0.date < next }
      let fetched = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
      var values: [Date: Int64] = [:]
      for month in months.dropLast() {
        if let value = try? await snapshotRepository.snapshot(month: month).netWorthMinor {
          values[month] = value
        }
      }
      guard !Task.isCancelled else { return }
      // Everything lands at once, so the charts draw one time instead of twice.
      withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
        transactions = fetched
        monthlyNetWorth = values
        hasLoaded = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      Task { await snapshotRepository.invalidate() }
      refreshVersion += 1
    }
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn, height: 420, showsTrail: false) }
        .ignoresSafeArea()
    }
    .navigationTitle("Insights")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: selectedBarMonth) { _, value in
      // Scrubbing pins the last month touched, so its button stays to open.
      if let value { pinnedBarMonth = value }
    }
    .onChange(of: selectedSpendingAngle) { _, value in
      if let value { pinnedGroupID = group(atAngle: value)?.id }
    }
    .sheet(item: $detail) { value in
      NavigationStack {
        List(transactions.filter { value.transactionIDs.contains($0.id) }.sorted { $0.date > $1.date }) { transaction in
          Button {
            editingTransaction = transaction
          } label: {
            HStack {
              MerchantLogoView(
                merchantName: transaction.kind == .transfer ? "" : transaction.payee,
                domain: transaction.kind == .transfer ? nil : PayeeDirectory.logoDomain(
                  for: transaction.payee, transactionDomain: transaction.merchantDomain, payees: payees
                ),
                kind: transaction.kind,
                envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name
              )
              VStack(alignment: .leading) {
                Text(transaction.payee.isEmpty ? transaction.kind.title : transaction.payee)
                  .foregroundStyle(Bow.ink)
                Text(transaction.date, style: .date)
                  .font(.bowSubhead)
                  .foregroundStyle(Bow.inkSoft)
              }
              Spacer()
              MoneyText(minor: transaction.amountMinor, currencyCode: currencyCode)
                .foregroundStyle(Bow.ink)
            }
          }
          .listRowBackground(Bow.card)
        }
        .bowListBackground()
        .overlay {
          if !transactions.contains(where: { value.transactionIDs.contains($0.id) }) {
            ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle")
          }
        }
        .navigationTitle(value.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button { detail = nil } label: { BowToolbarLabel("Done") } } }
        .sheet(item: $editingTransaction) { transaction in
          TransactionEditorScreen(
            subject: .existing(transaction),
            accounts: accounts,
            envelopes: envelopes,
            payees: payees,
            currencyCode: currencyCode
          )
        }
      }
    }
  }
}

private struct InsightsMonth: Identifiable {
  var month: Date
  var incomeMinor: Int64
  var expenseMinor: Int64
  var netWorthMinor: Int64?
  var id: Date { month }
}

private struct InsightsGroup: Identifiable {
  var id: UUID
  var name: String
  var totalMinor: Int64
  var transactions: [BudgetTransaction]
}

private struct InsightsDetail: Identifiable {
  var id = UUID()
  var title: String
  var transactionIDs: Set<UUID>

  init(title: String, transactions: [BudgetTransaction]) {
    self.title = title
    transactionIDs = Set(transactions.map(\.id))
  }
}

private extension View {
  func insightCard() -> some View {
    self.padding(Bow.Space.s5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .bowCard()
  }
}
