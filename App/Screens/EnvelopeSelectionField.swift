import SwiftUI
import SwiftData

struct EnvelopeSelectionField: View {
  var title: String
  @Binding var selection: UUID?
  var envelopes: [BudgetEnvelope]
  var noneTitle: String? = nil
  /// Shows the title as an icon-tile label, as in the editor sheets.
  var systemImage: String? = nil
  /// Shows the empty choice in amber, when saving needs an envelope.
  var highlightsNone = false
  /// Shown in place of the empty choice's title while nothing is chosen, e.g. on a new transaction.
  var prompt: String? = nil
  @State private var showingSelection = false

  private var valueStyle: Color {
    if envelopes.contains(where: { $0.id == selection }) { return Bow.ink }
    return highlightsNone ? Bow.needsInk : Bow.inkSoft
  }

  private var selectedName: String {
    if let envelope = envelopes.first(where: { $0.id == selection }) { return envelope.name }
    return prompt ?? noneTitle ?? "Choose an envelope"
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        BowFieldTitle(title: title, systemImage: systemImage)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(valueStyle)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.up.chevron.down")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkFaint)
      }
      .contentShape(Rectangle())
    }
    .sensoryFeedback(.selection, trigger: selection)
    .accessibilityLabel("\(title), \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      EnvelopeSelectionSheet(
        selectedID: selection,
        noneTitle: noneTitle
      ) { id in
        selection = id
        showingSelection = false
      }
    }
  }
}

struct EnvelopeScopeSelectionField: View {
  @Binding var selection: TransactionEnvelopeScope
  var envelopes: [BudgetEnvelope]
  /// Shows the title as an icon-tile label, as in the editor sheets.
  var systemImage: String? = nil
  @State private var showingSelection = false

  private var selectedName: String {
    switch selection {
    case .all: "All envelopes"
    case .uncategorized: "Items without an envelope"
    case .envelope(let id): envelopes.first(where: { $0.id == id })?.name ?? "All envelopes"
    }
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        BowFieldTitle(title: "Envelope", systemImage: systemImage)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(Bow.inkSoft)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkFaint)
      }
      .contentShape(Rectangle())
    }
    .accessibilityLabel("Envelope, \(selectedName)")
    .sheet(isPresented: $showingSelection) {
      EnvelopeSelectionSheet(
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

struct EnvelopeSelectionSheet: View {
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
                title: "Needs an envelope", balance: nil,
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
                envelopeButton(envelope, snapshot: currentSnapshot)
              }
            }
            .listRowBackground(Bow.card)
          }
        }
        let ungrouped = matchingEnvelopes(in: nil)
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in
              envelopeButton(envelope, snapshot: currentSnapshot)
            }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .searchable(text: $searchText, prompt: "Search envelopes")
      .navigationTitle("Envelope")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Cancel") }
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

  private func envelopeButton(_ envelope: BudgetEnvelope, snapshot: BudgetSnapshot?) -> some View {
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
