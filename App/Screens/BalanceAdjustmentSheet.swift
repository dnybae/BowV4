import SwiftUI
import SwiftData

/// A balance adjustment isn't spending, so it has nothing to edit: it explains itself and can be
/// deleted, which puts the account back at the balance it had before.
struct BalanceAdjustmentSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  var transaction: BudgetTransaction
  var accountName: String
  var currencyCode: String
  @State private var showingDelete = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: Bow.Space.s2) {
            MoneyText(minor: transaction.amountMinor, currencyCode: currencyCode,
                      showsPlusSign: transaction.amountMinor > 0)
              .font(.bowLargeTitle)
              .foregroundStyle(Bow.ink)
            Text("Balance adjustment")
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Bow.Space.s4)
          .listRowBackground(Color.clear)
          .accessibilityElement(children: .combine)
        }
        Section {
          LabeledContent("Account", value: accountName)
          LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .omitted))
        } footer: {
          Text("Bow recorded this when you changed \(accountName)’s balance. It moves the balance without counting as spending, so it never needs an envelope.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
        BowDestructiveSection("Delete adjustment") { showingDelete = true }
      }
      .bowListBackground()
      .navigationTitle("Adjustment")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Done") }
        }
      }
      .confirmationDialog("Delete this adjustment?", isPresented: $showingDelete, titleVisibility: .visible) {
        Button("Delete Adjustment", role: .destructive) { delete() }
      } message: {
        Text("\(accountName) goes back to the balance it had before this adjustment.")
      }
      .bowErrorAlert("Couldn’t delete adjustment", message: $errorMessage)
    }
  }

  private func delete() {
    do {
      try BudgetCommands.deleteTransaction(transaction, in: modelContext)
      toasts?.show(.deleted("Deleted adjustment"))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// Shown when a sheet's transaction or schedule was removed before it opened, e.g. by a bank sync.
struct MissingItemSheet: View {
  @Environment(\.dismiss) private var dismiss
  var title: String

  var body: some View {
    NavigationStack {
      ContentUnavailableView {
        Label("\(title) not found", systemImage: "questionmark.folder")
      } description: {
        Text("It may have been deleted or merged with a bank transaction.")
      } actions: {
        Button("Close") { dismiss() }
          .bowSecondaryButton(size: .regular)
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Done") }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
