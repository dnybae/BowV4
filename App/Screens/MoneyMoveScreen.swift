import SwiftUI
import SwiftData

struct MoneyMoveScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var snapshot: BudgetSnapshot
  var currencyCode: String
  var month: Date
  @State private var source: BudgetBucket
  @State private var target: BudgetBucket
  @State private var amount = ""
  @State private var errorMessage: String?

  init(
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    snapshot: BudgetSnapshot,
    currencyCode: String,
    month: Date,
    source: BudgetBucket,
    target: BudgetBucket
  ) {
    self.accounts = accounts
    self.envelopes = envelopes
    self.snapshot = snapshot
    self.currencyCode = currencyCode
    self.month = month
    _source = State(initialValue: source)
    _target = State(initialValue: target)
  }

  private var cardAccounts: [BudgetAccount] {
    accounts.filter { $0.kind == .credit }.sorted { $0.name < $1.name }
  }

  private var sourceAvailable: Int64 {
    switch source {
    case .readyToAssign: snapshot.readyToAssignMinor
    case .envelope(let id): snapshot.available(for: id)
    case .cardPayment(let id): snapshot.paymentAvailable[id, default: 0]
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          BudgetBucketSelectionField(
            title: "From", selection: $source,
            envelopes: envelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          BudgetBucketSelectionField(
            title: "To", selection: $target,
            envelopes: envelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          TextField("Amount", text: $amount)
            .keyboardType(.decimalPad)
        } header: {
          Text("Transfer")
        } footer: {
          Text("Available to move: \(BudgetMoney.formatted(max(0, sourceAvailable), currencyCode: currencyCode))")
        }
        Section {
          Text("This change applies to \(month.formatted(.dateTime.month(.wide).year())).")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Move Money")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Move") { save() }
            .disabled(amount.isEmpty || source == target)
        }
      }
      .alert("Couldn’t Move Money", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func save() {
    guard let minor = BudgetMoney.parseMinor(amount) else {
      errorMessage = "Enter a valid amount with no more than two decimal places."
      return
    }
    let now = Date()
    let allocationDate = Calendar.current.isDate(month, equalTo: now, toGranularity: .month)
      ? now
      : (Calendar.current.dateInterval(of: .month, for: month)?.start ?? month)
    do {
      try BudgetCommands.moveMoney(
        amountMinor: minor,
        from: source,
        to: target,
        snapshot: snapshot,
        date: allocationDate,
        in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
