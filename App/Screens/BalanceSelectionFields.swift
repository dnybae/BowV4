import SwiftUI
import SwiftData

struct AccountSelectionField: View {
  var title: String
  @Binding var selection: UUID?
  var accounts: [BudgetAccount]
  var excludingID: UUID? = nil
  var noneTitle: String? = nil
  @State private var showingSelection = false

  private var selectedName: String {
    if let account = accounts.first(where: { $0.id == selection }) { return account.name }
    return noneTitle ?? "Choose an account"
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        Text(title).foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .accessibilityLabel("\(title), \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      AccountSelectionSheet(
        title: title,
        selectedID: selection,
        excludingID: excludingID,
        noneTitle: noneTitle
      ) { id in
        selection = id
        showingSelection = false
      }
    }
  }
}

struct CategorySelectionField: View {
  var title: String
  @Binding var selection: UUID?
  var envelopes: [BudgetEnvelope]
  var noneTitle: String? = nil
  @State private var showingSelection = false

  private var selectedName: String {
    if let envelope = envelopes.first(where: { $0.id == selection }) { return envelope.name }
    return noneTitle ?? "Choose a category"
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        Text(title).foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .accessibilityLabel("\(title), \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      CategorySelectionSheet(
        selectedID: selection,
        noneTitle: noneTitle
      ) { id in
        selection = id
        showingSelection = false
      }
    }
  }
}

struct CategoryScopeSelectionField: View {
  @Binding var selection: TransactionEnvelopeScope
  var envelopes: [BudgetEnvelope]
  @State private var showingSelection = false

  private var selectedName: String {
    switch selection {
    case .all: "All Categories"
    case .uncategorized: "Needs Categorization"
    case .envelope(let id): envelopes.first(where: { $0.id == id })?.name ?? "All Categories"
    }
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        Text("Category").foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .accessibilityLabel("Category, \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      CategorySelectionSheet(
        selectedID: {
          if case .envelope(let id) = selection { return id }
          return nil
        }(),
        noneTitle: "All Categories",
        showsUncategorized: true,
        isUncategorizedSelected: selection == .uncategorized
      ) { id in
        selection = id.map(TransactionEnvelopeScope.envelope) ?? .all
        showingSelection = false
      } onSelectUncategorized: {
        selection = .uncategorized
        showingSelection = false
      }
    }
  }
}

struct BudgetBucketSelectionField: View {
  var title: String
  @Binding var selection: BudgetBucket
  var envelopes: [BudgetEnvelope]
  var cardAccounts: [BudgetAccount]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  @State private var showingSelection = false

  private var selectedName: String {
    switch selection {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): envelopes.first(where: { $0.id == id })?.name ?? "Category"
    case .cardPayment(let id):
      "\(cardAccounts.first(where: { $0.id == id })?.name ?? "Card") Payment"
    }
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        Text(title).foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .accessibilityLabel("\(title), \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      BudgetBucketSelectionSheet(
        title: title, selected: selection,
        envelopes: envelopes, cardAccounts: cardAccounts,
        snapshot: snapshot, currencyCode: currencyCode
      ) { bucket in
        selection = bucket
        showingSelection = false
      }
    }
  }
}

struct BudgetBucketSelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var groups: [BudgetGroup]
  var title: String
  var selected: BudgetBucket
  var envelopes: [BudgetEnvelope]
  var cardAccounts: [BudgetAccount]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var onSelect: (BudgetBucket) -> Void
  @State private var searchText = ""

  var body: some View {
    NavigationStack {
      List {
        if searchText.isEmpty {
          Section {
            Button {
              onSelect(.readyToAssign)
            } label: {
              SelectionRow(
                title: "Ready to Assign",
                balance: BudgetMoney.formatted(snapshot.readyToAssignMinor, currencyCode: currencyCode),
                isSelected: selected == .readyToAssign
              )
            }
          }
        }
        ForEach(groups.sorted { $0.sortOrder < $1.sortOrder }) { group in
          let matching = envelopes.filter {
            $0.groupID == group.id
              && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
          }.sorted { $0.sortOrder < $1.sortOrder }
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in categoryButton(envelope) }
            }
          }
        }
        let ungrouped = envelopes.filter { envelope in
          !groups.contains(where: { $0.id == envelope.groupID })
            && (searchText.isEmpty || envelope.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.sortOrder < $1.sortOrder }
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in categoryButton(envelope) }
          }
        }
        let matchingCards = cardAccounts.filter {
          searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        if !matchingCards.isEmpty {
          Section("Credit Card Payments") {
            ForEach(matchingCards) { account in
              Button {
                onSelect(.cardPayment(account.id))
              } label: {
                SelectionRow(
                  title: "\(account.name) Payment",
                  balance: BudgetMoney.formatted(
                    snapshot.paymentAvailable[account.id, default: 0],
                    currencyCode: currencyCode
                  ),
                  isSelected: selected == .cardPayment(account.id)
                )
              }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, prompt: "Search categories")
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }

  private func categoryButton(_ envelope: BudgetEnvelope) -> some View {
    Button {
      onSelect(.envelope(envelope.id))
    } label: {
      SelectionRow(
        title: envelope.name,
        balance: BudgetMoney.formatted(snapshot.available(for: envelope.id), currencyCode: currencyCode),
        isSelected: selected == .envelope(envelope.id),
        symbol: envelope.symbol
      )
    }
  }
}

struct AccountSelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var allocations: [BudgetAllocation]
  @Query private var transactions: [BudgetTransaction]
  var title: String
  var selectedID: UUID?
  var excludingID: UUID? = nil
  var noneTitle: String? = nil
  var onSelect: (UUID?) -> Void
  @State private var searchText = ""

  private var snapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: Date(), accounts: accounts, envelopes: envelopes,
      allocations: allocations, transactions: transactions
    )
  }

  var body: some View {
    NavigationStack {
      List {
        if let noneTitle, searchText.isEmpty {
          Button {
            onSelect(nil)
          } label: {
            SelectionRow(
              title: noneTitle, balance: nil,
              isSelected: selectedID == nil
            )
          }
        }
        ForEach(BudgetAccountKind.allCases) { kind in
          let matching = accounts.filter {
            $0.kind == kind && $0.id != excludingID
              && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
          }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
          if !matching.isEmpty {
            Section(kind.title) {
              ForEach(matching) { account in
                Button {
                  onSelect(account.id)
                } label: {
                  SelectionRow(
                    title: account.name,
                    balance: BudgetMoney.formatted(
                      snapshot.accountBalances[account.id, default: 0],
                      currencyCode: account.currencyCode
                    ),
                    isSelected: selectedID == account.id
                  )
                }
              }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, prompt: "Search accounts")
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }
}

struct CategorySelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var groups: [BudgetGroup]
  @Query private var allocations: [BudgetAllocation]
  @Query private var transactions: [BudgetTransaction]
  @Query private var profiles: [BudgetProfile]
  var selectedID: UUID?
  var noneTitle: String? = nil
  var showsUncategorized = false
  var isUncategorizedSelected = false
  var onSelect: (UUID?) -> Void
  var onSelectUncategorized: (() -> Void)? = nil
  @State private var searchText = ""

  private var snapshot: BudgetSnapshot {
    BudgetLedger.snapshot(
      month: Date(), accounts: accounts, envelopes: envelopes,
      allocations: allocations, transactions: transactions
    )
  }

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  var body: some View {
    NavigationStack {
      List {
        if searchText.isEmpty {
          if let noneTitle {
            Button {
              onSelect(nil)
            } label: {
              SelectionRow(
                title: noneTitle, balance: nil,
                isSelected: selectedID == nil && !isUncategorizedSelected
              )
            }
          }
          if showsUncategorized {
            Button {
              onSelectUncategorized?()
            } label: {
              SelectionRow(
                title: "Needs Categorization", balance: nil,
                isSelected: isUncategorizedSelected
              )
            }
          }
        }
        ForEach(groups.sorted { $0.sortOrder < $1.sortOrder }) { group in
          let matching = matchingEnvelopes(in: group.id)
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in
                categoryButton(envelope)
              }
            }
          }
        }
        let ungrouped = matchingEnvelopes(in: nil)
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in
              categoryButton(envelope)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, prompt: "Search categories")
      .navigationTitle("Category")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }

  private func matchingEnvelopes(in groupID: UUID?) -> [BudgetEnvelope] {
    envelopes.filter { envelope in
      (groupID == nil
        ? !groups.contains(where: { group in group.id == envelope.groupID })
        : envelope.groupID == groupID)
        && (searchText.isEmpty || envelope.name.localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.sortOrder < $1.sortOrder }
  }

  private func categoryButton(_ envelope: BudgetEnvelope) -> some View {
    Button {
      onSelect(envelope.id)
    } label: {
      SelectionRow(
        title: envelope.name,
        balance: BudgetMoney.formatted(snapshot.available(for: envelope.id), currencyCode: currencyCode),
        isSelected: selectedID == envelope.id && !isUncategorizedSelected,
        symbol: envelope.symbol
      )
    }
  }
}

private struct SelectionRow: View {
  var title: String
  var balance: String?
  var isSelected: Bool
  var symbol: String? = nil

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark")
        .font(.body.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 20)
        .opacity(isSelected ? 1 : 0)
        .accessibilityHidden(true)
      if let symbol {
        Image(systemName: symbol)
          .foregroundStyle(.tint)
          .frame(width: 24)
          .accessibilityHidden(true)
      }
      Text(title)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let balance {
        Text(balance)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityValue(isSelected ? "Selected" : "")
  }
}
