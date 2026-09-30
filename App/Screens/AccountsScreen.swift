import SwiftUI
import SwiftData

struct AccountsScreen: View {
  var accounts: [BudgetAccount]
  var balanceReport: AccountBalanceReport
  var currencyCode: String
  var onAddAccount: () -> Void
  var onViewInsights: () -> Void
  var onSelectTransaction: (UUID) -> Void
  @Query private var simpleFINLinks: [SimpleFINAccountLink]
  @AppStorage("bow.collapsedAccountGroups") private var collapsedAccountGroups = ""
  @State private var editingAccount: BudgetAccount?

  private var balances: [UUID: Int64] { balanceReport.balances }
  private var netWorthText: String {
    balanceReport.netWorthMinor.map { BudgetMoney.formatted($0, currencyCode: currencyCode) }
      ?? "Unavailable"
  }

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
          Label("No Accounts Yet", systemImage: "banknote.fill")
        } description: {
          Text("Add an account to start tracking your balances.")
        } actions: {
          Button("Add Account", systemImage: "plus", action: onAddAccount)
            .bowPrimaryButton()
        }
        .frame(maxWidth: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 30) {
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 32)
      }
    }
    .background {
      Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .mint) }
        .ignoresSafeArea()
    }
    .navigationTitle("Accounts")
    .navigationDestination(for: AccountRoute.self) { route in
      if let account = accounts.first(where: { $0.id == route.id }) {
        AccountDetailScreen(
          account: account,
          balanceMinor: balances[account.id, default: 0],
          currencyCode: currencyCode,
          onSelectTransaction: onSelectTransaction,
          onEditAccount: { editingAccount = account }
        )
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

  @ViewBuilder
  private func budgetGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Bow.inkSoft)
        .padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }

  @ViewBuilder
  private func accountGroup(_ kind: BudgetAccountKind, title: String) -> some View {
    let matching = accounts.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    if !matching.isEmpty {
      let total = matching.reduce(0) { $0 + balances[$1.id, default: 0] }
      let formattedTotal = BudgetMoney.formatted(total, currencyCode: currencyCode)
      VStack(alignment: .leading, spacing: 12) {
        Button {
          withAnimation(.smooth) { toggleGroup(kind) }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: collapsedKinds.contains(kind) ? "chevron.right" : "chevron.down")
              .font(.caption.weight(.semibold))
              .frame(width: 16)
              .accessibilityHidden(true)
            Text(title)
              .font(.headline)
            Spacer(minLength: 8)
            Text(formattedTotal)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .foregroundStyle(Bow.ink)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), total \(formattedTotal)")
        .accessibilityValue(collapsedKinds.contains(kind) ? "Collapsed" : "Expanded")

        if !collapsedKinds.contains(kind) {
          VStack(spacing: 0) {
            ForEach(matching) { account in
              accountRow(account)
              if account.id != matching.last?.id {
                Divider()
                  .overlay(Bow.line)
                  .padding(.leading, 64)
              }
            }
          }
          .bowCard()
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
        Text(netWorthText)
          .bowHeroFont()
          .monospacedDigit()
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .accessibilityElement(children: .combine)

      Button(action: onViewInsights) {
        HStack(spacing: Bow.Space.s1) {
          Text("View insights")
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
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
    collapsedAccountGroups = updated.map(\.rawValue).sorted().joined(separator: ",")
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
    return NavigationLink(value: AccountRoute(id: account.id)) {
      HStack(spacing: Bow.Space.s3) {
        Image(systemName: account.kind.systemImage)
          .bowScaledIcon(frame: 36, glyph: 15, weight: .semibold)
          .foregroundStyle(Bow.bowInk)
          .background(Bow.bowTint, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(account.name)
            .font(.bowBody)
            .foregroundStyle(Bow.ink)
          Text(syncText)
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        Text(balanceText)
          .font(.bowAmount)
          .monospacedDigit()
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Bow.inkFaint)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Bow.Space.s4)
      .padding(.vertical, Bow.Space.s3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(account.name), \(balanceText), \(syncText)")
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
  @State private var showingReconciliation = false
  @State private var feed = TransactionFeedModel()

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
    let onBudget = account.kind == .cash || account.kind == .credit
    parts.append("\(account.accountType.title), \(onBudget ? "on budget" : "off budget").")
    if !account.note.isEmpty { parts.append(account.note) }
    return parts.joined(separator: " ")
  }

  private func stat(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
      Text(value)
        .font(.bowAmount)
        .monospacedDigit()
        .foregroundStyle(Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .accessibilityElement(children: .combine)
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: Bow.Space.s4) {
          VStack(alignment: .leading, spacing: Bow.Space.s1) {
            Text("Balance")
              .font(.bowSubhead.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
            Text(BudgetMoney.formatted(balanceMinor, currencyCode: currencyCode))
              .bowHeroFont()
              .monospacedDigit()
              .foregroundStyle(Bow.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
          }
          .accessibilityElement(children: .combine)

          if link?.reportedBalance != nil || account.lastReconciledBalanceMinor != nil {
            HStack(alignment: .top, spacing: Bow.Space.s4) {
              if let reported = link?.reportedBalance {
                stat("Bank says", value: BudgetMoney.formatted(bankAmount: reported, currencyCode: currencyCode))
              }
              if let date = account.lastReconciledAt, let balance = account.lastReconciledBalanceMinor {
                stat("Reconciled \(date.formatted(.dateTime.month(.abbreviated).day()))",
                     value: BudgetMoney.formatted(balance, currencyCode: currencyCode))
              }
            }
          }

          Button("Reconcile", systemImage: "checkmark") {
            showingReconciliation = true
          }
          .bowSecondaryButton()
          .frame(maxWidth: .infinity)
        }
        .padding(Bow.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bowCard(radius: Bow.Radius.xl)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      } footer: {
        Text(detailCaption)
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
      }

      if feed.items.isEmpty && !feed.isLoading {
        Section("Ledger") {
          ContentUnavailableView("No transactions yet", systemImage: "list.bullet.rectangle")
        }
        .listRowBackground(Bow.card)
      } else {
        ForEach(TransactionDateGroup.make(feed.items)) { group in
          Section(group.title) {
            ForEach(group.items) { transaction in
            if transaction.isBalanceAdjustment {
              TransactionSummaryRow(
                transaction: transaction,
                currencyCode: currencyCode,
                displayAmountMinor: transaction.transferAccountID == account.id
                  ? -transaction.amountMinor : transaction.amountMinor,
                showsDate: false
              )
            } else {
              Button {
                onSelectTransaction(transaction.id)
              } label: {
                TransactionSummaryRow(
                  transaction: transaction,
                  currencyCode: currencyCode,
                  displayAmountMinor: transaction.transferAccountID == account.id
                    ? -transaction.amountMinor : transaction.amountMinor,
                  showsDate: false
                )
              }
              .buttonStyle(.plain)
            }
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
    }
    .bowListBackground()
    .navigationTitle(account.name)
    .task(id: account.id) {
      await feed.reload(container: modelContext.container, searchText: "", filter: TransactionFilter(),
                        scopedAccountID: account.id, includeUncategorizedCount: false,
                        includesBalanceAdjustments: true)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit Account", systemImage: "pencil", action: onEditAccount)
      }
    }
    .sheet(isPresented: $showingReconciliation) {
      ReconciliationScreen(account: account, currencyCode: currencyCode)
    }
  }
}
