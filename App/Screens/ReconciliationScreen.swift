import SwiftUI
import SwiftData

struct ReconciliationScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var account: BudgetAccount
  var transactions: [BudgetTransaction]
  var currencyCode: String
  @State private var statementDate = Date()
  @State private var statementBalance = ""
  @State private var selectedIDs: Set<UUID> = []
  @State private var didLoad = false
  @State private var errorMessage: String?

  private var calculator: ReconciliationCalculator { ReconciliationCalculator() }
  private var entries: [ReconciliationEntry] {
    calculator.entries(accountID: account.id, transactions: transactions.map {
      ReconciliationLedgerItem(
        id: $0.id,
        date: $0.date,
        amountMinor: $0.amountMinor,
        accountID: $0.accountID,
        transferAccountID: $0.transferAccountID,
        isCleared: $0.isCleared,
        destinationIsCleared: $0.destinationIsCleared
      )
    }, through: statementDate)
  }
  private var enteredBalance: Int64? { BudgetMoney.parseMinor(statementBalance) }
  private var clearedBalance: Int64 {
    calculator.clearedBalance(openingBalanceMinor: account.openingBalanceMinor, entries: entries, selectedIDs: selectedIDs)
  }
  private var difference: Int64? { enteredBalance.map { $0 - clearedBalance } }

  var body: some View {
    NavigationStack {
      List {
        Section {
          DatePicker("Statement date", selection: $statementDate, in: ...Date(), displayedComponents: .date)
          TextField("Statement balance", text: $statementBalance)
            .keyboardType(.numbersAndPunctuation)
        } header: {
          Text("Statement")
        } footer: {
          Text("Enter the balance shown by your bank on the statement date.")
        }
        Section("Difference") {
          LabeledContent("Cleared balance", value: BudgetMoney.formatted(clearedBalance, currencyCode: currencyCode))
          if let difference {
            LabeledContent("Difference", value: BudgetMoney.formatted(difference, currencyCode: currencyCode))
              .foregroundStyle(difference == 0 ? .green : .orange)
          } else {
            Text("Enter a statement balance to compare.")
              .foregroundStyle(.secondary)
          }
        }
        Section {
          if entries.isEmpty {
            ContentUnavailableView("No entries by this date", systemImage: "list.bullet.rectangle")
          } else {
            ForEach(entries) { entry in
              Button {
                if !selectedIDs.insert(entry.id).inserted { selectedIDs.remove(entry.id) }
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(entry.id) ? Color.accentColor : Color.secondary)
                    .font(.title3)
                  VStack(alignment: .leading) {
                    Text(transactions.first(where: { $0.id == entry.id })?.payee.isEmpty == false
                      ? transactions.first(where: { $0.id == entry.id })!.payee : "Transfer")
                      .foregroundStyle(.primary)
                    Text(entry.date, style: .date)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(BudgetMoney.formatted(entry.amountMinor, currencyCode: currencyCode))
                    .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(transactions.first(where: { $0.id == entry.id })?.payee ?? "Transfer"), \(BudgetMoney.formatted(entry.amountMinor, currencyCode: currencyCode)), \(selectedIDs.contains(entry.id) ? "cleared" : "uncleared")")
            }
          }
        } header: {
          HStack {
            Text("Transactions")
            Spacer()
            Button("Select All") { selectedIDs = Set(entries.map(\.id)) }
              .textCase(nil)
          }
        } footer: {
          Text("Select the transactions that cleared by your statement date. Reconciliation does not add or remove money.")
        }
      }
      .navigationTitle("Reconcile \(account.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Finish") { finish() }
            .disabled(difference != 0)
        }
      }
      .onAppear {
        if !didLoad {
          selectedIDs = Set(entries.filter(\.isCleared).map(\.id))
          didLoad = true
        }
      }
      .onChange(of: statementDate) { _, _ in
        selectedIDs = Set(entries.filter(\.isCleared).map(\.id))
      }
      .alert("Couldn’t Reconcile", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func finish() {
    guard let enteredBalance, enteredBalance == clearedBalance else { return }
    let now = Date()
    for transaction in transactions where entries.contains(where: { $0.id == transaction.id }) {
      let selected = selectedIDs.contains(transaction.id)
      if transaction.accountID == account.id {
        transaction.isCleared = selected
        transaction.reconciledAt = selected ? now : nil
      } else if transaction.transferAccountID == account.id {
        transaction.destinationIsCleared = selected
        transaction.destinationReconciledAt = selected ? now : nil
      }
    }
    account.lastReconciledAt = statementDate
    account.lastReconciledBalanceMinor = enteredBalance
    do {
      try modelContext.save()
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }
}
