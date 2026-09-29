import SwiftUI
import SwiftData

struct PayeeSelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  var selectedName: String
  var onSelect: (BudgetPayee) -> Void
  @State private var searchText = ""
  @State private var brandResults: [BrandSearchResult] = []
  @State private var isSearching = false
  @State private var errorMessage: String?
  @State private var directoryEntries: [PayeeDirectory.Entry] = []
  @State private var isLoadingPayees = true
  @FocusState private var searchFocused: Bool

  private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var localEntries: [PayeeDirectory.Entry] {
    directoryEntries
      .filter {
        (!$0.isTransferOnly || $0.ruleID != nil)
          && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
      }
      .sorted {
        if $0.transactionCount != $1.transactionCount {
          return $0.transactionCount > $1.transactionCount
        }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
  }

  private var hasExactLocalMatch: Bool {
    localEntries.contains { PayeeDirectory.key($0.name) == PayeeDirectory.key(query) }
  }

  var body: some View {
    NavigationStack {
      List {
        if !localEntries.isEmpty {
          Section("Your Payees") {
            ForEach(localEntries) { entry in
              Button {
                selectLocal(entry)
              } label: {
                HStack(spacing: 12) {
                  MerchantLogoView(
                    merchantName: entry.name,
                    domain: payees.first(where: { $0.id == entry.ruleID })?.merchantDomain
                  )
                  Text(entry.name).foregroundStyle(.primary)
                  Spacer()
                  if PayeeDirectory.key(entry.name) == PayeeDirectory.key(selectedName) {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                  }
                }
                .contentShape(Rectangle())
              }
              .accessibilityLabel("Select \(entry.name)")
            }
          }
        }
        if !query.isEmpty && !hasExactLocalMatch {
          Section("New Payee") {
            Button {
              createNamedPayee()
            } label: {
              Label("Create \"\(query)\"", systemImage: "plus")
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Create payee named \(query)")
          }
        }
        if !brandResults.isEmpty {
          Section("Companies") {
            ForEach(brandResults) { brand in
              Button {
                selectBrand(brand)
              } label: {
                HStack(spacing: 12) {
                  MerchantLogoView(
                    merchantName: brand.name, domain: brand.domain,
                    logoURL: brand.compactLogoURL
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(brand.name).foregroundStyle(.primary)
                    Text(brand.domain).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
              }
              .accessibilityLabel("Select company \(brand.name), \(brand.domain)")
            }
          }
        } else if isSearching {
          Section("Companies") {
            ProgressView("Searching companies…")
          }
        }
        if localEntries.isEmpty && query.isEmpty && isLoadingPayees {
          ProgressView("Loading payees…")
            .frame(maxWidth: .infinity)
        } else if localEntries.isEmpty && query.isEmpty {
          ContentUnavailableView(
            "No payees yet", systemImage: "person.text.rectangle",
            description: Text("Search for a company or create a payee by name.")
          )
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, placement: .toolbar, prompt: "Search payees or companies")
      .searchFocused($searchFocused)
      .navigationTitle("Payee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task {
        directoryEntries = (try? await PayeeDirectoryRepository(modelContainer: modelContext.container).entries()) ?? []
        isLoadingPayees = false
      }
      .task {
        try? await Task.sleep(for: .milliseconds(250))
        if !Task.isCancelled { searchFocused = true }
      }
      .task(id: query) {
        let requestedQuery = query
        brandResults = []
        isSearching = false
        guard requestedQuery.count >= 2 && BrandLookupClient.isConfigured else { return }
        do {
          try await Task.sleep(for: .milliseconds(200))
          try Task.checkCancellation()
          isSearching = true
          let results = try await BrandLookupClient.search(requestedQuery)
          try Task.checkCancellation()
          guard query == requestedQuery else { return }
          brandResults = results
          isSearching = false
        } catch is CancellationError {
          if query == requestedQuery { isSearching = false }
        } catch {
          if query == requestedQuery { isSearching = false }
        }
      }
      .alert("Couldn’t Save Payee", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
    .presentationDetents([.large])
  }

  private func selectLocal(_ entry: PayeeDirectory.Entry) {
    if let ruleID = entry.ruleID {
      let predicate = #Predicate<BudgetPayee> { $0.id == ruleID }
      let existing = payees.first(where: { $0.id == ruleID })
        ?? (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.first
      if let existing {
        onSelect(existing)
        dismiss()
        return
      }
    }
    createPayee(name: entry.name, domain: nil)
  }

  private func createNamedPayee() {
    guard !query.isEmpty else { return }
    createPayee(name: query, domain: nil)
  }

  private func selectBrand(_ brand: BrandSearchResult) {
    createPayee(name: brand.name, domain: brand.domain)
  }

  private func createPayee(name: String, domain: String?) {
    do {
      let savedPayees = try modelContext.fetch(FetchDescriptor<BudgetPayee>())
      let payee: BudgetPayee
      if let existing = PayeeDirectory.matchingPayee(for: name, payees: savedPayees) {
        payee = existing
        if let domain { payee.merchantDomain = domain }
      } else {
        payee = BudgetPayee(name: name, merchantDomain: domain)
        modelContext.insert(payee)
      }
      try modelContext.save()
      onSelect(payee)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
