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
        Text(title).foregroundStyle(Bow.ink)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(Bow.inkSoft)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.up.chevron.down")
          .font(.subheadline)
          .foregroundStyle(Bow.inkFaint)
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
    case .all: "All envelopes"
    case .uncategorized: "Uncategorized legacy items"
    case .envelope(let id): envelopes.first(where: { $0.id == id })?.name ?? "All envelopes"
    }
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        Text("Category").foregroundStyle(Bow.ink)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(Bow.inkSoft)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.subheadline)
          .foregroundStyle(Bow.inkFaint)
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
        noneTitle: "All envelopes",
        showsUncategorized: false,
        isUncategorizedSelected: false
      ) { id in
        selection = id.map(TransactionEnvelopeScope.envelope) ?? .all
        showingSelection = false
      }
    }
  }
}

struct CategorySelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var groups: [BudgetGroup]
  @Query private var profiles: [BudgetProfile]
  var selectedID: UUID?
  var noneTitle: String? = nil
  var showsUncategorized = false
  var isUncategorizedSelected = false
  var onSelect: (UUID?) -> Void
  var onSelectUncategorized: (() -> Void)? = nil
  @State private var searchText = ""
  @State private var snapshot: BudgetSnapshot?

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
            .listRowBackground(Bow.card)
          }
          if showsUncategorized {
            Button {
              onSelectUncategorized?()
            } label: {
              SelectionRow(
                title: "Needs categorization", balance: nil,
                isSelected: isUncategorizedSelected
              )
            }
            .listRowBackground(Bow.card)
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
            .listRowBackground(Bow.card)
          }
        }
        let ungrouped = matchingEnvelopes(in: nil)
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in
              categoryButton(envelope, snapshot: currentSnapshot)
            }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
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
    .task {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      snapshot = try? await repository.snapshot(month: Date())
    }
  }

  private func matchingEnvelopes(in groupID: UUID?) -> [BudgetEnvelope] {
    envelopes.filter { envelope in
      envelope.paymentAccountID == nil && (groupID == nil
        ? !groups.contains(where: { group in group.id == envelope.groupID })
        : envelope.groupID == groupID)
        && (!envelope.isHidden || envelope.id == selectedID)
        && (searchText.isEmpty || envelope.name.localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.sortOrder < $1.sortOrder }
  }

  private func categoryButton(_ envelope: BudgetEnvelope, snapshot: BudgetSnapshot?) -> some View {
    Button {
      onSelect(envelope.id)
    } label: {
      SelectionRow(
        title: envelope.name,
        balance: snapshot.map { BudgetMoney.formatted($0.available(for: envelope.id), currencyCode: currencyCode) },
        isSelected: selectedID == envelope.id && !isUncategorizedSelected
      )
    }
  }
}
