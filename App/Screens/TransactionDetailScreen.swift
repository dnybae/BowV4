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
      ?? (transaction.kind == .inflow ? "Ready to Assign" : "Choose an envelope")
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
          VStack(spacing: Bow.Space.s2) {
            MerchantLogoView(
              merchantName: transaction.kind == .transfer ? "" : transaction.payee,
              domain: transaction.kind == .transfer ? nil : PayeeDirectory.logoDomain(
                for: transaction.payee, transactionDomain: transaction.merchantDomain, payees: payees
              ),
              kind: transaction.kind,
              categoryName: envelopes.first { $0.id == transaction.envelopeID }?.name,
              size: 52
            )
            Text(transaction.payee.isEmpty ? "Transaction" : transaction.payee)
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            Text(BudgetMoney.formatted(transaction.amountMinor, currencyCode: currencyCode))
              .font(.bowHero)
              .monospacedDigit()
              .foregroundStyle(Bow.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
            Text(transaction.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
            Text(statusTitle)
              .font(.bowFootnote.weight(.medium))
              .foregroundStyle(needsLegacyReview ? Bow.needsInk : Bow.inkSoft)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Bow.Space.s4)
          .accessibilityElement(children: .combine)
        }
        .listRowBackground(Bow.card)

        Section {
          LabeledContent("Envelope", value: categoryName)
          LabeledContent("Account", value: accountName)
          if !transaction.notes.isEmpty {
            LabeledContent("Notes", value: transaction.notes)
          }
          LabeledContent("Cleared") {
            if transaction.isCleared {
              Label("Cleared", systemImage: "checkmark")
                .foregroundStyle(Bow.fundedInk)
            } else {
              Text("Not cleared")
            }
          }
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
            LabeledContent("Posted", value: record.date.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Matched", value: record.matchedAutomatically ? "Automatically" : "During review")
            Button("Unmatch bank transaction", role: .destructive) {
              showingUnmatchConfirmation = true
            }
          } header: {
            Text("From your bank")
          } footer: {
            Text("Unmatching keeps your entered transaction and returns the bank item to review.")
          }
          .listRowBackground(Bow.card)
        } else if bankRecord?.status == .imported {
          Section("From your bank") {
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
                envelopes: envelopes, noneTitle: "Choose an envelope"
              )
            }
            Button("Complete review", systemImage: "checkmark") { completeReview() }
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
      .alert("Couldn’t update transaction", isPresented: Binding(
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
