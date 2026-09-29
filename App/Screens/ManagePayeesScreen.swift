import SwiftUI
import SwiftData

struct ManagePayeesScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @State private var searchText = ""
  @State private var showingAdd = false
  @State private var directoryEntries: [PayeeDirectory.Entry] = []
  @State private var isLoading = true
  @State private var refreshVersion = 0

  private var entries: [PayeeDirectory.Entry] {
    directoryEntries.filter {
      searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var transferEntries: [PayeeDirectory.Entry] {
    entries.filter { $0.isTransferOnly && $0.transactionCount > 0 }
  }

  private var frequentEntries: [PayeeDirectory.Entry] {
    entries.filter { !$0.isTransferOnly && $0.transactionCount >= 2 }
      .sorted {
        $0.transactionCount == $1.transactionCount
          ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
          : $0.transactionCount > $1.transactionCount
      }
  }

  private var otherEntries: [PayeeDirectory.Entry] {
    entries.filter { !$0.isTransferOnly && $0.transactionCount < 2 }
  }

  private var alphabeticalSections: [PayeeAlphabetSection] {
    let grouped = Dictionary(grouping: otherEntries) { entry in
      let folded = entry.name.folding(options: .diacriticInsensitive, locale: .current)
      let initial = folded.localizedUppercase.first.map(String.init) ?? "#"
      guard let scalar = initial.unicodeScalars.first,
            CharacterSet.letters.contains(scalar) else { return "#" }
      return initial
    }
    return grouped.keys.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }.map { letter in
      PayeeAlphabetSection(
        letter: letter,
        entries: (grouped[letter] ?? []).sorted {
          $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
      )
    }
  }

  var body: some View {
    List {
      if entries.isEmpty && isLoading {
        ProgressView("Loading payees…")
          .frame(maxWidth: .infinity)
      } else if entries.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty ? "No payees yet" : "No matching payees",
          systemImage: "person.text.rectangle",
          description: Text(searchText.isEmpty
            ? "Add a payee or record a transaction to see it here."
            : "Try a different name.")
        )
      } else {
        if !transferEntries.isEmpty {
          Section("Transfers") {
            ForEach(transferEntries) { entry in payeeRow(entry) }
          }
        }
        if !frequentEntries.isEmpty {
          Section("Frequently Used") {
            ForEach(frequentEntries) { entry in payeeRow(entry) }
          }
        }
        ForEach(alphabeticalSections) { section in
          Section {
            ForEach(section.entries) { entry in payeeRow(entry) }
          } header: {
            VStack(alignment: .leading, spacing: 8) {
              if section.id == alphabeticalSections.first?.id {
                Text("All Payees")
              }
              Text(section.letter)
            }
          }
        }
      }
    }
    .searchable(text: $searchText, prompt: "Search payees")
    .navigationTitle("Manage Payees")
    .task(id: refreshVersion) {
      isLoading = true
      let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
      directoryEntries = (try? await repository.entries()) ?? []
      isLoading = false
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Payee", systemImage: "plus") { showingAdd = true }
      }
    }
    .sheet(isPresented: $showingAdd) {
      PayeeEditorScreen(entry: nil)
    }
  }

  private func payeeRow(_ entry: PayeeDirectory.Entry) -> some View {
    NavigationLink {
      PayeeDetailScreen(payeeKey: entry.key)
    } label: {
      HStack {
        MerchantLogoView(
          merchantName: entry.name,
          domain: payees.first(where: { $0.id == entry.ruleID })?.merchantDomain
        )
        Text(entry.name)
        Spacer(minLength: 12)
        Text(entry.transactionCount, format: .number)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(entry.name), \(entry.transactionCount) transactions")
    }
  }
}

private struct PayeeAlphabetSection: Identifiable {
  var letter: String
  var entries: [PayeeDirectory.Entry]

  var id: String { letter }
}
