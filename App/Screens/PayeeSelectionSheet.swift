import SwiftUI
import SwiftData

struct PayeeSelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  var selectedName: String
  var onSelect: (BudgetPayee) -> Void
  @State private var searchText = ""
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
        if localEntries.isEmpty && query.isEmpty && isLoadingPayees {
          ProgressView("Loading payees…")
            .frame(maxWidth: .infinity)
        } else if localEntries.isEmpty && query.isEmpty {
          ContentUnavailableView(
            "No payees yet", systemImage: "person.text.rectangle",
            description: Text("Search your payees or create one by name.")
          )
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $searchText, placement: .toolbar, prompt: "Search payees")
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
    createPayee(name: entry.name)
  }

  private func createNamedPayee() {
    guard !query.isEmpty else { return }
    createPayee(name: query)
  }

  private func createPayee(name: String) {
    do {
      let savedPayees = try modelContext.fetch(FetchDescriptor<BudgetPayee>())
      let payee: BudgetPayee
      if let existing = PayeeDirectory.matchingPayee(for: name, payees: savedPayees) {
        payee = existing
      } else {
        payee = BudgetPayee(name: name)
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
