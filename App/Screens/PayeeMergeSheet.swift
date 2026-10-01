import SwiftUI
import SwiftData

/// Picks a duplicate payee and folds it into the target payee.
struct PayeeMergeSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  var target: PayeeDirectory.Entry
  var onMerged: () -> Void
  @State private var entries: [PayeeDirectory.Entry] = []
  @State private var isLoading = true
  @State private var searchText = ""
  @State private var pendingSource: PayeeDirectory.Entry?
  @State private var isMerging = false
  @State private var errorMessage: String?

  private var candidates: [PayeeDirectory.Entry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return entries.filter {
      $0.key != target.key && !$0.isTransferOnly
        && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if isLoading {
          Section {
            BowTransactionSkeletonRows(count: 4)
          }
          .listRowBackground(Bow.card)
        } else if candidates.isEmpty {
          ContentUnavailableView(
            searchText.isEmpty ? "No other payees" : "No matching payees",
            systemImage: "person.text.rectangle",
            description: Text(searchText.isEmpty ? "Payees you can merge will appear here." : "Try a different name.")
          )
        } else {
          Section {
            ForEach(candidates) { entry in
              Button {
                pendingSource = entry
              } label: {
                HStack(spacing: 12) {
                  MerchantLogoView(
                    merchantName: entry.name,
                    domain: payees.first(where: { $0.id == entry.ruleID })?.merchantDomain
                  )
                  Text(entry.name).foregroundStyle(Bow.ink)
                  Spacer(minLength: 12)
                  Text(entry.transactionCount, format: .number)
                    .font(.bowSubhead)
                    .foregroundStyle(Bow.inkSoft)
                }
                .contentShape(Rectangle())
              }
              .disabled(isMerging)
              .accessibilityLabel("\(entry.name), \(entry.transactionCount) transactions")
            }
          } footer: {
            Text("Choose a payee that’s really \(target.name). Its transactions and schedules move here, and its name is saved as a bank name so future imports land here too.")
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .searchable(text: $searchText, prompt: "Search payees")
      .navigationTitle("Merge into \(target.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task {
        entries = (try? await PayeeDirectoryRepository(modelContainer: modelContext.container).entries()) ?? []
        isLoading = false
      }
      .confirmationDialog(
        "Merge “\(pendingSource?.name ?? "")” into “\(target.name)”?",
        isPresented: Binding(
          get: { pendingSource != nil },
          set: { if !$0 { pendingSource = nil } }
        ),
        titleVisibility: .visible,
        presenting: pendingSource
      ) { source in
        Button("Merge") { Task { await merge(source) } }
        Button("Cancel", role: .cancel) {}
      } message: { source in
        Text("^[\(source.transactionCount) transaction](inflect: true) and ^[\(source.scheduleCount) schedule](inflect: true) will move to \(target.name). \(target.name) keeps its own settings and picks up any it’s missing. This can’t be undone.")
      }
      .alert("Couldn’t merge payees", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func merge(_ source: PayeeDirectory.Entry) async {
    guard !isMerging else { return }
    isMerging = true
    defer { isMerging = false }
    do {
      try await PayeeDirectoryRepository(modelContainer: modelContext.container).merge(
        sourceKey: source.key, sourceName: source.name,
        into: target.key, targetName: target.name
      )
      onMerged()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
