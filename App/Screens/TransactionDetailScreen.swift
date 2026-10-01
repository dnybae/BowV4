import SwiftUI
import SwiftData

struct TransactionDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.currentPayeeKey) private var currentPayeeKey
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

  private var envelopeName: String {
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
    Form {
      Section {
        BowIdentityHeader(
          name: transaction.payee.isEmpty ? "Transaction" : transaction.payee,
          context: "\(accountName), \(transaction.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
          amountMinor: transaction.amountMinor,
          currencyCode: currencyCode,
          pill: statusPill
        ) {
          MerchantLogoView(
            merchantName: transaction.kind == .transfer ? "" : transaction.payee,
            domain: transaction.kind == .transfer ? nil : PayeeDirectory.logoDomain(
              for: transaction.payee, transactionDomain: transaction.merchantDomain, payees: payees
            ),
            kind: transaction.kind,
            envelopeName: envelopes.first { $0.id == transaction.envelopeID }?.name,
            size: 64, style: .glossy
          )
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      Section {
        payeeRow
        BowTileValueRow("Envelope", systemImage: "square.grid.2x2", value: envelopeName)
        BowTileValueRow("Account", systemImage: "creditcard", value: accountName)
        BowTileValueRow("Date", systemImage: "calendar",
                        value: transaction.date.formatted(date: .abbreviated, time: .omitted))
        if !transaction.notes.isEmpty {
          BowTileValueRow("Notes", systemImage: "note.text", value: transaction.notes)
        }
      }
      .listRowBackground(Bow.card)

      if let record = bankRecord, record.status == .linked {
        Section {
          bankRows(record)
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
      } else if let record = bankRecord, record.status == .imported {
        Section {
          bankRows(record)
        } header: {
          Text("From your bank")
        } footer: {
          Text("Added from a posted bank transaction.")
        }
        .listRowBackground(Bow.card)
      }

      if needsLegacyReview {
        Section {
          if transaction.kind == .expense {
            EnvelopeSelectionField(
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
    .bowSkyList(mood: needsLegacyReview || transaction.needsApproval ? .review : .dawn, height: 460)
    .navigationTitle("Transaction")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
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
    .bowErrorAlert("Couldn’t update transaction", message: $message)
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      let id = transaction.id
      if (try? BudgetTransactionLookup.byID(id, in: modelContext)) == nil {
        dismiss()
      }
    }
    .onAppear { reviewEnvelopeID = transaction.envelopeID }
  }

  /// Transfers and blank payees have no payee page. Opened from a payee's own page, the row
  /// isn't a link, so the user can't loop payee → transaction → same payee.
  @ViewBuilder
  private var payeeRow: some View {
    if transaction.kind != .transfer, !transaction.payee.isEmpty {
      let key = PayeeDirectory.canonicalKey(for: transaction.payee, payees: payees)
      if key == currentPayeeKey {
        BowTileValueRow("Payee", systemImage: "person", value: transaction.payee)
      } else {
        NavigationLink {
          PayeeDetailScreen(payeeKey: key)
        } label: {
          BowTileValueRow(title: "Payee", systemImage: "person") {
            Text(transaction.payee).lineLimit(1)
          }
        }
        .accessibilityHint("Opens payee details")
      }
    }
  }

  /// Cleared, Needs review, or how the transaction got here.
  private var statusPill: StatusPill {
    if needsLegacyReview || transaction.needsApproval
      || (transaction.kind == .expense && transaction.envelopeID == nil) {
      return .needsReview
    }
    if transaction.isCleared { return .cleared }
    return StatusPill(text: statusTitle, state: .empty)
  }

  @ViewBuilder
  private func bankRows(_ record: SimpleFINImportRecord) -> some View {
    LabeledContent("Bank description", value: record.payee)
    LabeledContent("Posted", value: record.date.formatted(date: .abbreviated, time: .omitted))
    LabeledContent("Posted amount") {
      MoneyText(minor: record.amountMinor, currencyCode: currencyCode)
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

/// Transaction details presented on their own: adds the navigation stack and a Done button.
struct TransactionDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  var transaction: BudgetTransaction
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var payees: [BudgetPayee]
  var currencyCode: String

  var body: some View {
    NavigationStack {
      TransactionDetailScreen(
        transaction: transaction, accounts: accounts, envelopes: envelopes,
        payees: payees, currencyCode: currencyCode
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .bowToastHost()
  }
}

extension EnvironmentValues {
  /// The payee whose page is showing, so its own transactions don't link back to it.
  @Entry var currentPayeeKey: String? = nil
}
