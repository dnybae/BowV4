import SwiftUI
import SwiftData

struct AccountsScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var accounts: [BudgetAccount]
  var balanceReport: AccountBalanceReport
  var currencyCode: String
  var onAddAccount: () -> Void
  var onViewInsights: () -> Void
  var onSelectTransaction: (UUID) -> Void
  /// Opens a new transaction already set to this account.
  var onAddTransaction: (UUID) -> Void
  /// An account was deleted from its editor; close its detail screen.
  var onAccountRemoved: () -> Void = {}
  @Query private var simpleFINLinks: [SimpleFINAccountLink]
  /// Held in @State, not @AppStorage, so collapsing animates; saved to UserDefaults on change.
  @State private var collapsedKinds = Self.savedCollapsedKinds
  @State private var reconcilingAccount: BudgetAccount?
  @State private var editingAccount: BudgetAccount?
  @State private var showsClosedAccounts = UserDefaults.standard.bool(forKey: "bow.showsClosedAccountGroup")
  @Namespace private var zoomNamespace

  private var balances: [UUID: Int64] { balanceReport.balances }

  private var openAccounts: [BudgetAccount] { accounts.filter { $0.closedAt == nil } }

  private var closedAccounts: [BudgetAccount] {
    accounts.filter { $0.closedAt != nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static let collapsedGroupsKey = "bow.collapsedAccountGroups"

  private static var savedCollapsedKinds: Set<BudgetAccountKind> {
    let saved = UserDefaults.standard.string(forKey: collapsedGroupsKey) ?? ""
    return Set(saved.split(separator: ",").compactMap { BudgetAccountKind(rawValue: String($0)) })
  }

  var body: some View {
    List {
      if accounts.isEmpty {
        ContentUnavailableView {
          Label("No accounts yet", systemImage: "banknote.fill")
        } description: {
          Text("Add the accounts your money lives in, like checking, savings or a credit card, to start budgeting it.")
        } actions: {
          Button("Add Account", systemImage: "plus", action: onAddAccount)
            .bowPrimaryButton()
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      } else {
        Section {
          netWorthCard
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }

        accountGroup(.cash, title: "Cash", context: "On budget")
        accountGroup(.credit, title: "Credit", context: openAccounts.contains { $0.kind == .cash } ? nil : "On budget")
        accountGroup(.asset, title: "Investments", context: "Off budget")
        accountGroup(.liability, title: "Loans", context: openAccounts.contains { $0.kind == .asset } ? nil : "Off budget")

        if !closedAccounts.isEmpty {
          closedGroup
        }
      }
    }
    .scrollsToTopOnReselect(of: .accounts)
    .bowListBackground { Bow.mist }
    .bowSoftScrollEdge()
    .navigationTitle("Accounts")
    .sensoryFeedback(.selection, trigger: collapsedKinds)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: AccountRoute.self) { route in
      if let account = accounts.first(where: { $0.id == route.id }) {
        AccountDetailScreen(
          account: account,
          balanceMinor: balances[account.id, default: 0],
          currencyCode: currencyCode,
          onSelectTransaction: onSelectTransaction,
          onEditAccount: { editingAccount = account },
          onAddTransaction: { onAddTransaction(account.id) }
        )
        .navigationTransition(.zoom(sourceID: route, in: zoomNamespace))
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onAddAccount) { BowToolbarLabel("Add Account", systemImage: "plus") }
      }
    }
    .sheet(item: $reconcilingAccount) { account in
      ReconciliationScreen(account: account, currencyCode: currencyCode)
    }
    .sheet(item: $editingAccount) { account in
      NavigationStack {
        AccountEditorScreen(currencyCode: currencyCode, account: account, onDeleted: onAccountRemoved)
      }
    }
  }

  /// One native section per account kind, keeping the on/off-budget hierarchy.
  @ViewBuilder
  private func accountGroup(_ kind: BudgetAccountKind, title: String, context: String?) -> some View {
    let matching = openAccounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    if !matching.isEmpty {
      let summary = groupSummary(for: matching)
      let isCollapsed = collapsedKinds.contains(kind)
      Section {
        if isCollapsed {
          Button { toggleGroup(kind) } label: {
            BowGroupSummaryRow(
              count: Text("^[\(summary.count) account](inflect: true)"),
              totalMinor: summary.balanceMinor, totalLabel: "Balance", currencyCode: currencyCode
            ) {
              Text(updateSummary(summary))
                .foregroundStyle(Bow.inkSoft)
            }
          }
          .accessibilityValue("\(title), collapsed")
        } else {
          ForEach(matching, content: accountRow)
        }
      } header: {
        VStack(alignment: .leading, spacing: Bow.Space.s3) {
          if let context {
            Text(context)
              .font(.bowFootnote.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
              .accessibilityAddTraits(.isHeader)
          }
          BowGroupHeader(name: title, isCollapsed: isCollapsed, onToggle: { toggleGroup(kind) }) {
            if !isCollapsed {
              MoneyText(minor: summary.balanceMinor, currencyCode: currencyCode)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
          }
        }
        .textCase(nil)
      }
      .listRowBackground(Bow.card)
    }
  }

  /// Closed accounts, folded away under one header until asked for.
  private var closedGroup: some View {
    let summary = groupSummary(for: closedAccounts)
    return Section {
      if !showsClosedAccounts {
        Button { toggleClosedGroup() } label: {
          BowGroupSummaryRow(
            count: Text("^[\(summary.count) account](inflect: true)"),
            totalMinor: summary.balanceMinor, totalLabel: "Balance", currencyCode: currencyCode
          ) {
            Text("Excluded from net worth")
              .foregroundStyle(Bow.inkSoft)
          }
        }
        .accessibilityValue("Closed accounts, collapsed")
      } else {
        ForEach(closedAccounts, content: accountRow)
      }
    } header: {
      BowGroupHeader(name: "Closed", isCollapsed: !showsClosedAccounts, onToggle: {
        toggleClosedGroup()
      }) {
        if showsClosedAccounts {
          Text("^[\(closedAccounts.count) account](inflect: true)")
            .foregroundStyle(Bow.inkSoft)
        }
      }
    }
    .listRowBackground(Bow.card)
  }

  private func toggleClosedGroup() {
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) { showsClosedAccounts.toggle() }
    UserDefaults.standard.set(showsClosedAccounts, forKey: "bow.showsClosedAccountGroup")
  }

  private func groupSummary(for accounts: [BudgetAccount]) -> AccountGroupSummary {
    AccountGroupSummary(
      accounts: accounts, balances: balances,
      linkedAccountIDs: Set(simpleFINLinks.compactMap(\.localAccountID))
    )
  }

  private func updateSummary(_ summary: AccountGroupSummary) -> String {
    if summary.linkedCount == 0 { return "Updated by you" }
    if summary.manualCount == 0 { return "Linked to bank sync" }
    return "\(summary.linkedCount) linked · \(summary.manualCount) manual"
  }

  private var netWorthCard: some View {
    VStack(spacing: Bow.Space.s3) {
      VStack(spacing: Bow.Space.s1) {
        Text("Net worth")
          .font(.bowHeadline)
          .foregroundStyle(Bow.inkSoft)
        Group {
          if let netWorth = balanceReport.netWorthMinor {
            MoneyText(minor: netWorth, currencyCode: currencyCode)
          } else {
            Text("Unavailable")
          }
        }
        .bowHeroFont()
        .foregroundStyle(Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      }
      .accessibilityElement(children: .combine)

      Button(action: onViewInsights) {
        HStack(spacing: Bow.Space.s1) {
          Text("View insights")
          Image(systemName: "chevron.right")
            .font(.bowFootnote.weight(.semibold))
            .accessibilityHidden(true)
        }
      }
      .bowSecondaryButton(size: .regular)
      .fixedSize()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s6)
  }

  private func toggleGroup(_ kind: BudgetAccountKind) {
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      if !collapsedKinds.insert(kind).inserted {
        collapsedKinds.remove(kind)
      }
    }
    UserDefaults.standard.set(
      collapsedKinds.map(\.rawValue).sorted().joined(separator: ","), forKey: Self.collapsedGroupsKey
    )
  }

  private func syncDescription(for account: BudgetAccount) -> String {
    guard let link = simpleFINLinks.first(where: { $0.localAccountID == account.id }) else {
      return "Updated by you"
    }
    guard let reportedAt = link.reportedAt else { return "Linked to bank sync" }
    return "Synced \(reportedAt.formatted(.relative(presentation: .named)))"
  }

  private func accountRow(_ account: BudgetAccount) -> some View {
    let balance = balances[account.id, default: 0]
    let balanceText = BudgetMoney.formatted(balance, currencyCode: currencyCode)
    let syncText = syncDescription(for: account)
    let route = AccountRoute(id: account.id)
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Bow.Space.s2))
      : AnyLayout(HStackLayout(spacing: Bow.Space.s3))
    return NavigationLink(value: route) {
      layout {
        if !dynamicTypeSize.isAccessibilitySize {
          AccountLogoView(appearance: account.logoAppearance, systemImage: account.accountType.systemImage, size: 36)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(account.name)
            .font(.bowHeadline)
            .foregroundStyle(Bow.ink)
          Text(syncText)
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        MoneyText(minor: balance, currencyCode: currencyCode)
          .font(.bowAmount)
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .padding(.vertical, Bow.Space.s1)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .matchedTransitionSource(id: route, in: zoomNamespace)
    .contextMenu {
      if account.closedAt == nil {
        Button("Add Transaction", systemImage: "plus") { onAddTransaction(account.id) }
        Button("Reconcile", systemImage: "checkmark") { reconcilingAccount = account }
      }
      Button("Edit Account", systemImage: "pencil") { editingAccount = account }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(account.name)
    .accessibilityValue("\(balanceText), \(syncText)")
    .accessibilityAddTraits(.isButton)
  }
}

struct AccountRoute: Hashable {
  var id: UUID
}

private struct AccountDetailScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var simpleFINLinks: [SimpleFINAccountLink]
  var account: BudgetAccount
  var balanceMinor: Int64
  var currencyCode: String
  var onSelectTransaction: (UUID) -> Void
  var onEditAccount: () -> Void
  var onAddTransaction: () -> Void
  @State private var showingReconciliation = false
  @State private var feed = TransactionFeedModel()
  @State private var hasLoadedFeed = false
  /// Bumped by every save, so the ledger shows edits made from any sheet.
  @State private var refreshVersion = 0

  private var link: SimpleFINAccountLink? {
    simpleFINLinks.first { $0.localAccountID == account.id }
  }

  private var detailCaption: String {
    var parts: [String] = []
    if let link {
      if let reportedAt = link.reportedAt {
        parts.append("Synced with \(link.name) \(reportedAt.formatted(.relative(presentation: .named))).")
      } else {
        parts.append("Linked to \(link.name).")
      }
    }
    if !account.note.isEmpty { parts.append(account.note) }
    return parts.joined(separator: " ")
  }

  private var reconcileStats: [BowStat] {
    var stats: [BowStat] = []
    if let reported = link?.reportedBalance {
      stats.append(.text("Bank says", BudgetMoney.formatted(bankAmount: reported, currencyCode: currencyCode)))
    }
    if let date = account.lastReconciledAt, let balance = account.lastReconciledBalanceMinor {
      stats.append(.money("Reconciled \(date.formatted(.dateTime.month(.abbreviated).day()))", balance))
    }
    return stats
  }

  private var isFirstLoad: Bool { feed.items.isEmpty && (!hasLoadedFeed || feed.isLoading) }

  var body: some View {
    List {
      Section {
        VStack(spacing: Bow.Space.s4) {
          BowIdentityHeader(
            name: account.name,
            context: "\(account.accountType.title), \(account.kind == .cash || account.kind == .credit ? "on budget" : "off budget")",
            amountMinor: balanceMinor,
            currencyCode: currencyCode
          ) {
            AccountLogoView(appearance: account.logoAppearance, systemImage: account.accountType.systemImage, size: 64, style: .glossy)
          }
          if !reconcileStats.isEmpty {
            BowStatStrip(stats: reconcileStats, currencyCode: currencyCode)
          }
          BowActionTileRow {
            BowActionTile("Add", systemImage: "plus", isProminent: true, action: onAddTransaction)
            BowActionTile("Reconcile", systemImage: "checkmark.seal") { showingReconciliation = true }
            BowActionTile("Edit", systemImage: "pencil", action: onEditAccount)
          }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
      } footer: {
        if link != nil || !account.note.isEmpty {
          Text(detailCaption)
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
      }

      if isFirstLoad {
        Section("Ledger") {
          BowTransactionSkeletonRows()
        }
        .listRowBackground(Bow.card)
      } else if feed.items.isEmpty {
        Section("Ledger") {
          // The Add tile above is the action, so the empty state only explains.
          ContentUnavailableView {
            Label("No transactions in \(account.name) yet", systemImage: "list.bullet.rectangle")
          } description: {
            Text("Tap Add above to enter one by hand, or link this account to your bank to bring them in automatically.")
          }
        }
        .listRowBackground(Bow.card)
      } else {
        ForEach(TransactionDateGroup.make(feed.items)) { group in
          Section(group.title) {
            ForEach(group.items) { transaction in
              let model = TransactionRowModel(
                transaction,
                amountMinor: transaction.transferAccountID == account.id
                  ? -transaction.amountMinor : transaction.amountMinor
              )
              Button {
                onSelectTransaction(transaction.id)
              } label: {
                TransactionRowView(model: model, currencyCode: currencyCode, options: .hidesAccount)
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
    .bowListBackground()
    .bowAnimation(value: feed.items.map(\.id))
    .bowAnimation(value: isFirstLoad)
    .navigationTitle(account.name)
    .navigationBarTitleDisplayMode(.inline)
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .task(id: AccountLedgerKey(accountID: account.id, refreshVersion: refreshVersion)) {
      // Several saves in a row (a sync, an edit with an adjustment) reload once.
      if hasLoadedFeed { try? await Task.sleep(for: .milliseconds(150)) }
      guard !Task.isCancelled else { return }
      await feed.reload(container: modelContext.container, searchText: "", filter: TransactionFilter(),
                        scopedAccountID: account.id, includeUncategorizedCount: false,
                        includesBalanceAdjustments: true)
      hasLoadedFeed = true
    }
    .sheet(isPresented: $showingReconciliation) {
      ReconciliationScreen(account: account, currencyCode: currencyCode)
    }
  }
}

private struct AccountLedgerKey: Hashable {
  var accountID: UUID
  var refreshVersion: Int
}
