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
        allowedIDs: Set(accounts.map(\.id)),
        excludingID: excludingID,
        noneTitle: noneTitle
      ) { id in
        selection = id
        showingSelection = false
      }
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
  var allowedIDs: Set<UUID>
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
        let currentSnapshot = snapshot
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
            $0.kind == kind && allowedIDs.contains($0.id) && $0.id != excludingID
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
                      currentSnapshot.accountBalances[account.id, default: 0],
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
