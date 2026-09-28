import SwiftUI
import SwiftData

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
        let currentSnapshot = snapshot
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
                categoryButton(envelope, snapshot: currentSnapshot)
              }
            }
          }
        }
        let ungrouped = matchingEnvelopes(in: nil)
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in
              categoryButton(envelope, snapshot: currentSnapshot)
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

  private func categoryButton(_ envelope: BudgetEnvelope, snapshot: BudgetSnapshot) -> some View {
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
