import SwiftUI
import SwiftData

struct SimpleFINLinkPickerScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var connections: [SimpleFINConnection]
  @Query private var links: [SimpleFINAccountLink]
  var account: BudgetAccount
  @State private var message: String?
  @State private var isWorking = false

  private var currentLink: SimpleFINAccountLink? {
    links.first { $0.localAccountID == account.id }
  }
  private var choices: [SimpleFINAccountLink] {
    links.filter {
      $0.currencyCode == account.currencyCode
        && ($0.localAccountID == nil || $0.localAccountID == account.id)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Choose the bank account that belongs to \(account.name). New bank activity will sync here. Transactions already in Bow stay where they are.")
            .font(.subheadline).foregroundStyle(Bow.inkSoft)
        }
        .listRowBackground(Bow.card)
        if choices.isEmpty {
          ContentUnavailableView(
            "No bank accounts available", systemImage: "link",
            description: Text("Connect another account in SimpleFIN, then sync to see it here.")
          )
        } else {
          Section("Bank accounts") {
            ForEach(choices) { link in
              Button {
                Task { await select(link) }
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(link.name).foregroundStyle(Bow.ink)
                    if let balance = link.reportedBalance {
                      Text("Bank balance: \(BudgetMoney.formatted(bankAmount: balance, currencyCode: link.currencyCode))")
                        .font(.caption).foregroundStyle(Bow.inkSoft)
                    }
                  }
                  Spacer()
                  if link.id == currentLink?.id {
                    Image(systemName: "checkmark")
                      .foregroundStyle(.tint)
                      .accessibilityHidden(true)
                  }
                }
                .contentShape(Rectangle())
              }
              .disabled(isWorking || link.id == currentLink?.id)
              .accessibilityAddTraits(link.id == currentLink?.id ? .isSelected : [])
            }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle("Linked bank account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Bank sync", isPresented: Binding(
        get: { message != nil }, set: { if !$0 { message = nil } }
      )) {
        Button("OK") { message = nil }
      } message: {
        Text(message ?? "")
      }
    }
  }

  private func select(_ link: SimpleFINAccountLink) async {
    guard let connection = connections.first else { return }
    isWorking = true
    defer { isWorking = false }
    let previousLink = currentLink
    let previousStart = link.importStartDate
    let previousChange = connection.lastMappingChangeAt
    previousLink?.localAccountID = nil
    link.localAccountID = account.id
    link.importStartDate = Date()
    connection.lastMappingChangeAt = Date()
    var linkSaved = false
    do {
      try modelContext.save()
      linkSaved = true
      _ = try await SimpleFINSyncCoordinator.shared.sync(in: modelContext, manual: true)
      dismiss()
    } catch {
      if linkSaved {
        message = "The bank link was saved, but the first sync could not finish. Try Sync Now in Settings → SimpleFIN. \(error.localizedDescription)"
      } else {
        previousLink?.localAccountID = account.id
        link.localAccountID = nil
        link.importStartDate = previousStart
        connection.lastMappingChangeAt = previousChange
        message = error.localizedDescription
      }
    }
  }
}
