import SwiftUI
import SwiftData

struct TransactionDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var records: [SimpleFINImportRecord]
  var transaction: BudgetTransaction
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var payees: [BudgetPayee]
  var currencyCode: String
  @State private var showingEditor = false
  @State private var showingUnmatchConfirmation = false
  @State private var message: String?

  private var bankRecord: SimpleFINImportRecord? {
    records.first { $0.transactionID == transaction.id && $0.status != .ignored }
  }

  private var accountName: String {
    accounts.first { $0.id == transaction.accountID }?.name ?? "Account"
  }

  private var categoryName: String {
    if transaction.kind == .transfer { return "Transfer" }
    return envelopes.first { $0.id == transaction.envelopeID }?.name
      ?? (transaction.kind == .inflow ? "Ready to Assign" : "Needs Categorization")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text(transaction.payee.isEmpty ? "Transaction" : transaction.payee)
              .font(.title2.weight(.semibold))
            Text(BudgetMoney.formatted(transaction.amountMinor, currencyCode: currencyCode))
              .font(.largeTitle.weight(.bold))
            Text(statusTitle)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(transaction.needsApproval
                ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
          }
          .padding(.vertical, 12)
        }

        Section("Details") {
          LabeledContent("Account", value: accountName)
          LabeledContent("Category", value: categoryName)
          LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .omitted))
          if !transaction.notes.isEmpty {
            LabeledContent("Notes", value: transaction.notes)
          }
          LabeledContent("Cleared", value: transaction.isCleared ? "Yes" : "No")
        }

        if let record = bankRecord, record.status == .linked {
          Section {
            LabeledContent("Bank description", value: record.payee)
            LabeledContent("Posted amount", value: BudgetMoney.formatted(
              record.amountMinor, currencyCode: currencyCode
            ))
            LabeledContent("Posted date", value: record.date.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Matched", value: record.matchedAutomatically ? "Automatically" : "During review")
            Button("Unmatch Bank Transaction", role: .destructive) {
              showingUnmatchConfirmation = true
            }
          } header: {
            Text("Match details")
          } footer: {
            Text("Unmatching keeps your entered transaction and returns the bank item to review.")
          }
        } else if bankRecord?.status == .imported {
          Section("Bank import") {
            Text("Added from a posted bank transaction.")
              .foregroundStyle(.secondary)
          }
        }

        if transaction.needsApproval {
          Section {
            Button("Approve Transaction", systemImage: "checkmark") {
              transaction.needsApproval = false
              do { try modelContext.save(); dismiss() }
              catch { message = error.localizedDescription }
            }
          } footer: {
            Text("Approve this imported transaction after checking its details. You can edit it first.")
          }
        }
      }
      .navigationTitle("Transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Edit", systemImage: "pencil") { showingEditor = true }
        }
      }
      .sheet(isPresented: $showingEditor) {
        TransactionEditorScreen(
          transaction: transaction, accounts: accounts,
          envelopes: envelopes, payees: payees, currencyCode: currencyCode
        )
      }
      .confirmationDialog("Unmatch this bank transaction?", isPresented: $showingUnmatchConfirmation) {
        Button("Unmatch", role: .destructive) {
          guard let bankRecord else { return }
          do { try SimpleFINSyncCoordinator.shared.unmatch(bankRecord, in: modelContext) }
          catch { message = error.localizedDescription }
        }
      } message: {
        Text("The manual transaction stays in Spending. The posted bank item returns to Bank Review.")
      }
      .alert("Could Not Update Transaction", isPresented: Binding(
        get: { message != nil }, set: { if !$0 { message = nil } }
      )) {
        Button("OK") { message = nil }
      } message: {
        Text(message ?? "")
      }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        let id = transaction.id
        if (try? BudgetTransactionLookup.byID(id, in: modelContext)) == nil {
          dismiss()
        }
      }
    }
  }

  private var statusTitle: String {
    if transaction.needsApproval { return "Needs review" }
    if bankRecord?.status == .linked { return "Matched with bank" }
    if bankRecord?.status == .imported || transaction.sourceRaw == "simplefin" { return "Imported from bank" }
    if transaction.sourceRaw == "manualLinked" { return "Matched with bank" }
    return transaction.isCleared ? "Cleared" : "Entered manually"
  }
}
