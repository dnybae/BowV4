import SwiftUI

/// Picks where money for a cover comes from: Ready to Assign pinned first, then every
/// visible envelope that has money, grouped in budget order.
struct CoverDonorPickerScreen: View {
  var excluded: Set<BudgetBucket>
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var envelopes: [BudgetEnvelope]
  var groups: [BudgetGroup]
  var onSelect: (BudgetBucket) -> Void
  @State private var searchText = ""

  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted { $0.sortOrder == $1.sortOrder
      ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
      : $0.sortOrder < $1.sortOrder }
  }

  private var showsReadyToAssign: Bool {
    snapshot.readyToAssignMinor > 0 && !excluded.contains(.readyToAssign)
      && (searchText.isEmpty || "Ready to Assign".localizedCaseInsensitiveContains(searchText))
  }

  private func donors(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter {
      $0.groupID == group.id && !$0.isHidden && $0.paymentAccountID == nil
        && snapshot.available(for: $0.id) > 0 && !excluded.contains(.envelope($0.id))
        && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
          || group.name.localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    let sections = orderedGroups.map { ($0, donors(in: $0)) }.filter { !$0.1.isEmpty }
    List {
      if showsReadyToAssign {
        Section("Pinned") {
          donorButton("Ready to Assign", amount: snapshot.readyToAssignMinor, bucket: .readyToAssign)
        }
        .listRowBackground(Bow.card)
      }
      ForEach(sections, id: \.0.id) { group, envelopes in
        Section(group.name) {
          ForEach(envelopes) { envelope in
            donorButton(envelope.name, amount: snapshot.available(for: envelope.id), bucket: .envelope(envelope.id))
          }
        }
        .listRowBackground(Bow.card)
      }
      if sections.isEmpty && !showsReadyToAssign {
        if searchText.isEmpty {
          ContentUnavailableView(
            "No Money to Move", systemImage: "tray",
            description: Text("Assign money or add income, then come back to cover this envelope.")
          )
          .listRowBackground(Color.clear)
        } else {
          ContentUnavailableView.search(text: searchText)
            .listRowBackground(Color.clear)
        }
      }
    }
    .bowListBackground()
    .searchable(text: $searchText, prompt: "Search envelopes")
    .navigationTitle("Cover from")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func donorButton(_ name: String, amount: Int64, bucket: BudgetBucket) -> some View {
    Button {
      onSelect(bucket)
    } label: {
      HStack(spacing: Bow.Space.s3) {
        Text(name)
          .font(.bowBody)
          .foregroundStyle(Bow.ink)
        Spacer(minLength: Bow.Space.s2)
        StatusPill(text: BudgetMoney.formatted(amount, currencyCode: currencyCode), state: .funded)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .accessibilityLabel("\(name), \(BudgetMoney.formatted(amount, currencyCode: currencyCode)) available")
  }
}
