import SwiftUI
import SwiftData

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
            $0.groupID == group.id && !$0.isHidden
              && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
          }.sorted { $0.sortOrder < $1.sortOrder }
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in categoryButton(envelope) }
            }
          }
        }
        let ungrouped = envelopes.filter { envelope in
          !groups.contains(where: { $0.id == envelope.groupID }) && !envelope.isHidden
            && (searchText.isEmpty || envelope.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.sortOrder < $1.sortOrder }
        if !ungrouped.isEmpty {
          Section("Other") {
            ForEach(ungrouped) { envelope in categoryButton(envelope) }
          }
        }
        let hidden = envelopes.filter {
          $0.isHidden && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.name < $1.name }
        if !hidden.isEmpty {
          Section("Hidden Envelopes") {
            ForEach(hidden) { envelope in categoryButton(envelope) }
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
        isSelected: selected == .envelope(envelope.id)
      )
    }
  }
}
