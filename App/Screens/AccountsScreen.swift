import SwiftUI
import SwiftData

struct AccountsScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var accounts: [BudgetAccount]
  var balanceReport: AccountBalanceReport
  var currencyCode: String
  var onAddAccount: () -> Void
  var onViewInsights: () -> Void
  var onSelectTransaction: (UUID) -> Void
  /// Opens a new transaction already set to this account.
  var onAddTransaction: (UUID) -> Void
  @Query private var simpleFINLinks: [SimpleFINAccountLink]
  @AppStorage("bow.collapsedAccountGroups") private var collapsedAccountGroups = ""
  @State private var editingAccount: BudgetAccount?
  @Namespace private var zoomNamespace

  private var balances: [UUID: Int64] { balanceReport.balances }

  private var hasOnBudgetAccounts: Bool {
    accounts.contains { $0.kind == .cash || $0.kind == .credit }
  }

  private var hasOffBudgetAccounts: Bool {
    accounts.contains { $0.kind == .asset || $0.kind == .liability }
  }

  private var collapsedKinds: Set<BudgetAccountKind> {
    Set(collapsedAccountGroups.split(separator: ",").compactMap {
      BudgetAccountKind(rawValue: String($0))
    })
  }

  var body: some View {
    ScrollView {
      if accounts.isEmpty {
        ContentUnavailableView {
          Label("No accounts yet", systemImage: "banknote.fill")
        } description: {
          Text("Add the accounts your money lives in, like checking, savings or a credit card, to start budgeting it.")
        } actions: {
          Button("Add Account", systemImage: "plus", action: onAddAccount)
            .bowPrimaryButton()
        }
        .frame(maxWidth: .infinity)
      } else {
        VStack(alignment: .leading, spacing: Bow.Space.s6) {
          netWorthCard

          if hasOnBudgetAccounts {
            budgetGroup("On budget") {
              accountGroup(.cash, title: "Cash")
              accountGroup(.credit, title: "Credit")
            }
          }

          if hasOffBudgetAccounts {
            budgetGroup("Off budget") {
              accountGroup(.asset, title: "Investments")
              accountGroup(.liability, title: "Loans")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Bow.Space.s5)
        .padding(.top, Bow.Space.s3)
        .padding(.bottom, Bow.Space.s8)
      }
    }
    .scrollsToTopOnReselect(of: .accounts)
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .mint) }
        .ignoresSafeArea()
    }
    .bowSoftScrollEdge()
    .navigationTitle("Accounts")
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
        Button("Add Account", systemImage: "plus", action: onAddAccount)
      }
    }
    .sheet(item: $editingAccount) { account in
      NavigationStack {
        AccountEditorScreen(currencyCode: currencyCode, account: account)
      }
    }
  }

  /// "On budget" / "Off budget": a quiet label over its account groups.
  private func budgetGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Bow.Space.s4) {
      Text(title)
        .font(.bowFootnote.weight(.semibold))
        .foregroundStyle(Bow.inkSoft)
        .padding(.leading, Bow.Space.s1)
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }

  /// One kind of account, as separate cards like Budget's envelopes, under the same header.
  @ViewBuilder
  private func accountGroup(_ kind: BudgetAccountKind, title: String) -> some View {
    let matching = accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    if !matching.isEmpty {
      let total = matching.reduce(0) { $0 + balances[$1.id, default: 0] }
      let isCollapsed = collapsedKinds.contains(kind)
      VStack(alignment: .leading, spacing: Bow.Space.s2) {
        BowGroupHeader(name: title, isCollapsed: isCollapsed, onToggle: { toggleGroup(kind) }) {
          MoneyText(minor: total, currencyCode: currencyCode)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(.leading, Bow.Space.s1)

        if !isCollapsed {
          ForEach(matching) { account in
            accountCard(account)
              .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
          }
        }
      }
    }
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
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s6)
  }

  private func toggleGroup(_ kind: BudgetAccountKind) {
    var updated = collapsedKinds
    if !updated.insert(kind).inserted {
      updated.remove(kind)
    }
    withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
      collapsedAccountGroups = updated.map(\.rawValue).sorted().joined(separator: ",")
    }
  }

  private func syncDescription(for account: BudgetAccount) -> String {
    guard let link = simpleFINLinks.first(where: { $0.localAccountID == account.id }) else {
      return "Updated by you"
    }
    guard let reportedAt = link.reportedAt else { return "Linked to bank sync" }
    return "Synced \(reportedAt.formatted(.relative(presentation: .named)))"
  }

  private func accountCard(_ account: BudgetAccount) -> some View {
    let balance = balances[account.id, default: 0]
    let balanceText = BudgetMoney.formatted(balance, currencyCode: currencyCode)
    let syncText = syncDescription(for: account)
    let route = AccountRoute(id: account.id)
    return NavigationLink(value: route) {
      BowItemCard {
        HStack(spacing: Bow.Space.s3) {
          Image(systemName: account.kind.systemImage)
            .bowScaledIcon(frame: 36, glyph: 15, weight: .semibold)
            .foregroundStyle(Bow.bowInk)
            .background(Bow.bowTint, in: Circle())
            .accessibilityHidden(true)
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
            .minimumScaleFactor(0.85)
        }
        .padding(.vertical, Bow.Space.s3)
      }
    }
    .buttonStyle(.bowPress)
    .matchedTransitionSource(id: route, in: zoomNamespace)
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
            BowGlossyTile(systemImage: account.kind.systemImage)
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
          ContentUnavailableView {
            Label("No transactions in \(account.name) yet", systemImage: "list.bullet.rectangle")
          } description: {
            Text("Add one by hand, or link this account to your bank to bring them in automatically.")
          } actions: {
            Button("Add Transaction", systemImage: "plus", action: onAddTransaction)
              .bowPrimaryButton(size: .regular)
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
              if transaction.isBalanceAdjustment {
                TransactionRowView(model: model, currencyCode: currencyCode, options: .hidesAccount)
              } else {
                Button {
                  onSelectTransaction(transaction.id)
                } label: {
                  TransactionRowView(model: model, currencyCode: currencyCode, options: .hidesAccount)
                }
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
    .bowSkyList(mood: .dawn, height: 460)
    .bowAnimation(value: feed.items.map(\.id))
    .bowAnimation(value: isFirstLoad)
    .navigationTitle(account.name)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: account.id) {
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
