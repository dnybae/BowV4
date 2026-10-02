import SwiftUI
import SwiftData

struct BudgetBucketSelectionField: View {
  var title: String
  @Binding var selection: BudgetBucket
  var envelopes: [BudgetEnvelope]
  var cardAccounts: [BudgetAccount]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  /// Shows the title as an icon-tile label, as in the editor sheets.
  var systemImage: String? = nil
  @State private var showingSelection = false

  private var selectedName: String {
    switch selection {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): envelopes.first(where: { $0.id == id })?.name ?? "Envelope"
    case .cardPayment(let id):
      "\(cardAccounts.first(where: { $0.id == id })?.name ?? "Card") Payment"
    }
  }

  var body: some View {
    Button {
      showingSelection = true
    } label: {
      HStack(spacing: 12) {
        BowFieldTitle(title: title, systemImage: systemImage)
        Spacer(minLength: 12)
        Text(selectedName)
          .foregroundStyle(Bow.inkSoft)
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
          .listRowBackground(Bow.card)
        }
        ForEach(groups.sorted { $0.sortOrder < $1.sortOrder }) { group in
          let matching = envelopes.filter {
            $0.groupID == group.id && $0.paymentAccountID == nil && !$0.isHidden
              && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
          }.sorted { $0.sortOrder < $1.sortOrder }
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in envelopeButton(envelope) }
            }
            .listRowBackground(Bow.card)
          }
        }
        let ungrouped = envelopes.filter { envelope in
          !groups.contains(where: { $0.id == envelope.groupID }) && envelope.paymentAccountID == nil && !envelope.isHidden
            && (searchText.isEmpty || envelope.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.sortOrder < $1.sortOrder }
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in envelopeButton(envelope) }
          }
          .listRowBackground(Bow.card)
        }
        let hidden = envelopes.filter {
          $0.paymentAccountID == nil && $0.isHidden && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.name < $1.name }
        if !hidden.isEmpty {
          Section("Hidden envelopes") {
            ForEach(hidden) { envelope in envelopeButton(envelope) }
          }
          .listRowBackground(Bow.card)
        }
        let matchingCards = cardAccounts.filter {
          searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        if !matchingCards.isEmpty {
          Section("Credit card payments") {
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
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .searchable(text: $searchText, prompt: "Search envelopes")
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Cancel") }
        }
      }
    }
    .presentationDetents([.large])
  }

  private func envelopeButton(_ envelope: BudgetEnvelope) -> some View {
    Button {
      onSelect(.envelope(envelope.id))
    } label: {
      SelectionRow(
        title: envelope.name,
        balance: BudgetMoney.formatted(snapshot.available(for: envelope.id), currencyCode: currencyCode),
        isSelected: selected == .envelope(envelope.id)
      )
    }
  }
}
