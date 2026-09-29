import SwiftUI
import Charts
import SwiftData

struct InsightsScreen: View {
  @Query private var payees: [BudgetPayee]
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var allocations: [BudgetAllocation]
  var transactions: [BudgetTransaction]
  var schedules: [BudgetSchedule] = []
  var currencyCode: String
  @State private var selectedBarMonth: Date?
  @State private var selectedSpendingAngle: Double?
  @State private var detail: InsightsDetail?
  @State private var editingTransaction: BudgetTransaction?

  private var calendar: Calendar { .current }
  private var months: [Date] {
    let current = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    return (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
  }
  private var accountKinds: [UUID: BudgetAccountKind] {
    Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.kind) })
  }
  private var forecast: [BowForecastMonth] {
    let current = BudgetLedger.snapshot(month: Date(), accounts: accounts, envelopes: envelopes,
                                        allocations: allocations, transactions: transactions)
    return BowForecast().project(from: Date(), currentNetWorthMinor: current.netWorthMinor,
                                 transactions: transactions, schedules: schedules)
  }
  private var monthItems: [InsightsMonth] {
    months.map { month in
      let items = transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
      let income = items.filter { $0.kind == .inflow && accountKinds[$0.accountID] == .cash }
        .reduce(Int64(0)) { $0 + max(0, $1.amountMinor) }
      let expenses = items.filter { transaction in
        transaction.kind == .expense || (transaction.kind == .transfer
          && accountKinds[transaction.accountID] == .cash
          && [.asset, .liability].contains(accountKinds[transaction.transferAccountID ?? UUID()]))
      }.reduce(Int64(0)) { $0 + max(0, -$1.amountMinor) }
      let netWorth = BudgetLedger.snapshot(
        month: month,
        accounts: accounts,
        envelopes: envelopes,
        allocations: allocations,
        transactions: transactions
      ).netWorthMinor
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

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 5) {
          Text("See where your money goes")
            .font(.title2.weight(.semibold))
          Text("Six months of income, spending, and net worth")
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("Income & Spending").font(.headline)
          Chart {
            ForEach(monthItems) { item in
              BarMark(x: .value("Month", item.month, unit: .month), y: .value("Amount", Double(item.incomeMinor) / 100))
                .foregroundStyle(by: .value("Flow", "Income"))
                .position(by: .value("Flow", "Income"))
              BarMark(x: .value("Month", item.month, unit: .month), y: .value("Amount", Double(item.expenseMinor) / 100))
                .foregroundStyle(by: .value("Flow", "Spending"))
                .position(by: .value("Flow", "Spending"))
            }
          }
          .chartForegroundStyleScale(["Income": Color.green, "Spending": Color.orange])
          .chartXSelection(value: $selectedBarMonth)
          .frame(height: 220)
          Text("Tap a month to see its transactions.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .insightCard()

        VStack(alignment: .leading, spacing: 12) {
          Text("Spending by Group").font(.headline)
          Text((months.last ?? Date()).formatted(.dateTime.month(.wide).year()))
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if spendingGroups.isEmpty {
            ContentUnavailableView("No spending yet", systemImage: "chart.pie", description: Text("Categorized expenses will appear here."))
          } else {
            Chart(spendingGroups) { group in
              SectorMark(angle: .value("Spending", Double(group.totalMinor)), innerRadius: .ratio(0.65), angularInset: 2)
                .foregroundStyle(by: .value("Group", group.name))
            }
            .chartAngleSelection(value: $selectedSpendingAngle)
            .frame(height: 210)
            .accessibilityLabel("Spending by envelope group")
            ForEach(spendingGroups) { group in
              Button {
                detail = InsightsDetail(title: group.name, transactions: group.transactions)
              } label: {
                HStack {
                  Text(group.name)
                  Spacer()
                  Text(BudgetMoney.formatted(group.totalMinor, currencyCode: currencyCode))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .insightCard()

        VStack(alignment: .leading, spacing: 12) {
          Text("Net Worth").font(.headline)
          Chart(monthItems) { item in
            LineMark(x: .value("Month", item.month, unit: .month), y: .value("Net Worth", Double(item.netWorthMinor) / 100))
              .interpolationMethod(.catmullRom)
              .foregroundStyle(.tint)
            PointMark(x: .value("Month", item.month, unit: .month), y: .value("Net Worth", Double(item.netWorthMinor) / 100))
              .foregroundStyle(.tint)
          }
          .frame(height: 190)
          Text("Includes tracking accounts and credit balances.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .insightCard()

        VStack(alignment: .leading, spacing: 12) {
          Label("The Arrow", systemImage: "arrow.up.right")
            .font(.headline)
          Text("Shooting for financial freedom")
            .font(.title3.weight(.semibold))
          Text("Six-month net worth estimate from recent spending, income, and scheduled activity.")
            .font(.subheadline).foregroundStyle(.secondary)
          Chart {
            ForEach(monthItems.suffix(3)) { item in
              LineMark(x: .value("Month", item.month, unit: .month),
                       y: .value("Net Worth", Double(item.netWorthMinor) / 100))
                .foregroundStyle(.tint)
            }
            ForEach(forecast) { item in
              LineMark(x: .value("Month", item.month, unit: .month),
                       y: .value("Projected Net Worth", Double(item.netWorthMinor) / 100))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .foregroundStyle(.orange)
              PointMark(x: .value("Month", item.month, unit: .month),
                        y: .value("Projected Net Worth", Double(item.netWorthMinor) / 100))
                .foregroundStyle(.orange)
            }
          }
          .frame(height: 210)
          .accessibilityLabel("Net worth forecast for the next six months")
          if let last = forecast.last {
            LabeledContent("Projected in six months",
              value: BudgetMoney.formatted(last.netWorthMinor, currencyCode: currencyCode))
              .font(.subheadline.weight(.medium))
          }
          Text("Estimate only · Transfers between your own accounts do not change net worth.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .insightCard()
      }
      .padding(16)
      .padding(.bottom, 24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Insights")
    .onChange(of: selectedBarMonth) { _, value in
      guard let value else { return }
      let matching = transactions.filter { calendar.isDate($0.date, equalTo: value, toGranularity: .month) }
      detail = InsightsDetail(title: value.formatted(.dateTime.month(.wide).year()), transactions: matching)
      selectedBarMonth = nil
    }
    .onChange(of: selectedSpendingAngle) { _, value in
      guard let value else { return }
      var boundary = 0.0
      for group in spendingGroups {
        boundary += Double(group.totalMinor)
        if value <= boundary {
          detail = InsightsDetail(title: group.name, transactions: group.transactions)
          break
        }
      }
      selectedSpendingAngle = nil
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
                domain: transaction.kind == .transfer ? nil : transaction.merchantDomain
              )
              VStack(alignment: .leading) {
                Text(transaction.payee.isEmpty ? transaction.kind.title : transaction.payee)
                  .foregroundStyle(.primary)
                Text(transaction.date, style: .date)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(BudgetMoney.formatted(transaction.amountMinor, currencyCode: currencyCode))
                .foregroundStyle(.primary)
            }
          }
          .buttonStyle(.plain)
        }
        .overlay {
          if !transactions.contains(where: { value.transactionIDs.contains($0.id) }) {
            ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle")
          }
        }
        .navigationTitle(value.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
        .sheet(item: $editingTransaction) { transaction in
          TransactionEditorScreen(
            transaction: transaction,
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
  var netWorthMinor: Int64
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
    self.padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
  }
}
