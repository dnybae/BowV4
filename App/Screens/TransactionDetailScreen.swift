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
  @State private var reviewEnvelopeID: UUID?
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
      ?? (transaction.kind == .inflow ? "Ready to Assign" : "Choose an Envelope")
  }

  private var needsLegacyReview: Bool {
    bankRecord?.status != .imported
      && (transaction.needsApproval || (transaction.kind == .expense && transaction.envelopeID == nil))
  }

  private var canCompleteReview: Bool {
    transaction.kind != .expense || envelopes.contains {
      $0.id == reviewEnvelopeID && !$0.isHidden && $0.paymentAccountID == nil
    }
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
              .fontDesign(.rounded).monospacedDigit()
            Text(statusTitle)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(needsLegacyReview
                ? AnyShapeStyle(Bow.needsInk) : AnyShapeStyle(Bow.inkSoft))
          }
          .padding(.vertical, 12)
        }
        .listRowBackground(Bow.card)

        Section("Details") {
          LabeledContent("Account", value: accountName)
          LabeledContent("Category", value: categoryName)
          LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .omitted))
          if !transaction.notes.isEmpty {
            LabeledContent("Notes", value: transaction.notes)
          }
          LabeledContent("Cleared", value: transaction.isCleared ? "Yes" : "No")
        }
        .listRowBackground(Bow.card)

        if let record = bankRecord, record.status == .linked {
          Section {
            LabeledContent("Bank description", value: record.payee)
            LabeledContent("Posted amount") {
            Text(BudgetMoney.formatted(
                record.amountMinor, currencyCode: currencyCode
            ))
              .fontDesign(.rounded).monospacedDigit()
          }
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
          .listRowBackground(Bow.card)
        } else if bankRecord?.status == .imported {
          Section("Bank import") {
            Text("Added from a posted bank transaction.")
              .foregroundStyle(Bow.inkSoft)
          }
          .listRowBackground(Bow.card)
        }

        if needsLegacyReview {
          Section {
            if transaction.kind == .expense {
              CategorySelectionField(
                title: "Envelope", selection: $reviewEnvelopeID,
                envelopes: envelopes, noneTitle: "Choose an Envelope"
              )
            }
            Button("Complete Review", systemImage: "checkmark") { completeReview() }
              .disabled(!canCompleteReview)
          } footer: {
            Text("This older transaction needs a one-time check. Expenses must have an envelope before review can finish.")
          }
          .listRowBackground(Bow.card)
        } else if transaction.needsApproval
          || (transaction.kind == .expense && transaction.envelopeID == nil) {
          Section {
            Text("Finish this transaction in Spending → Bank Review.")
              .foregroundStyle(Bow.inkSoft)
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
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
      .onAppear { reviewEnvelopeID = transaction.envelopeID }
    }
  }

  private var statusTitle: String {
    if needsLegacyReview || transaction.needsApproval
      || (transaction.kind == .expense && transaction.envelopeID == nil) {
      return "Needs bank review"
    }
    if bankRecord?.status == .linked { return "Matched with bank" }
    if bankRecord?.status == .imported || transaction.sourceRaw == "simplefin" { return "Imported from bank" }
    if transaction.sourceRaw == "manualLinked" { return "Matched with bank" }
    return transaction.isCleared ? "Cleared" : "Entered manually"
  }

  private func completeReview() {
    guard canCompleteReview else { return }
    transaction.envelopeID = reviewEnvelopeID
    transaction.needsApproval = false
    do { try modelContext.save(); dismiss() }
    catch { message = error.localizedDescription }
  }
}
