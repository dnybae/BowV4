import SwiftUI

struct TransactionFilterScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Binding private var filters: TransactionFilter
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var currencyCode: String
  @State private var draft: TransactionFilter
  @State private var usesStartDate: Bool
  @State private var usesEndDate: Bool
  @State private var startDate: Date
  @State private var endDate: Date
  @State private var minimumAmount: String
  @State private var maximumAmount: String

  init(
    filters: Binding<TransactionFilter>,
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    currencyCode: String
  ) {
    _filters = filters
    self.accounts = accounts
    self.envelopes = envelopes
    self.currencyCode = currencyCode
    let current = filters.wrappedValue
    _draft = State(initialValue: current)
    _usesStartDate = State(initialValue: current.startDate != nil)
    _usesEndDate = State(initialValue: current.endDate != nil)
    _startDate = State(initialValue: current.startDate ?? Date())
    _endDate = State(initialValue: current.endDate ?? Date())
    _minimumAmount = State(initialValue: current.minimumAmountMinor.map(BudgetMoney.editable) ?? "")
    _maximumAmount = State(initialValue: current.maximumAmountMinor.map(BudgetMoney.editable) ?? "")
  }

  private var parsedMinimum: Int64? { BudgetMoney.parseMinor(minimumAmount) }
  private var parsedMaximum: Int64? { BudgetMoney.parseMinor(maximumAmount) }

  private var canApply: Bool {
    let minimumIsValid = minimumAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || (parsedMinimum ?? -1) >= 0
    let maximumIsValid = maximumAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || (parsedMaximum ?? -1) >= 0
    let amountRangeIsValid: Bool
    if let parsedMinimum, let parsedMaximum {
      amountRangeIsValid = parsedMinimum <= parsedMaximum
    } else {
      amountRangeIsValid = true
    }
    let dateRangeIsValid = !usesStartDate || !usesEndDate
      || Calendar.current.compare(startDate, to: endDate, toGranularity: .day)
        != .orderedDescending
    return minimumIsValid && maximumIsValid && amountRangeIsValid && dateRangeIsValid
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          AccountSelectionField(
            title: "Account", selection: $draft.accountID,
            accounts: accounts, noneTitle: "All Accounts"
          )
        }

        Section("Category") {
          CategoryScopeSelectionField(selection: $draft.envelopeScope, envelopes: envelopes)
        }

        Section("Status") {
          Picker("Show", selection: $draft.status) {
            ForEach(TransactionStatusScope.allCases, id: \.self) { status in
              Text(status.title).tag(status)
            }
          }
          .pickerStyle(.menu)
        }

        Section("Date Range") {
          Toggle("From Date", isOn: $usesStartDate)
          if usesStartDate {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
              .datePickerStyle(.compact)
          }
          Toggle("Through Date", isOn: $usesEndDate)
          if usesEndDate {
            DatePicker("Through", selection: $endDate, displayedComponents: .date)
              .datePickerStyle(.compact)
          }
        }

        Section {
          TextField("Minimum", text: $minimumAmount)
            .keyboardType(.decimalPad)
          TextField("Maximum", text: $maximumAmount)
            .keyboardType(.decimalPad)
        } header: {
          Text("Amount (\(currencyCode))")
        } footer: {
          Text("Enter positive amounts. Outflows are filtered by their absolute value.")
        }

        Section {
          Button("Clear All Filters") {
            filters = TransactionFilter()
            dismiss()
          }
        }
      }
      .navigationTitle("Filter Transactions")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") { apply() }
            .disabled(!canApply)
        }
      }
    }
  }

  private func apply() {
    draft.startDate = usesStartDate ? startDate : nil
    draft.endDate = usesEndDate ? endDate : nil
    draft.minimumAmountMinor = parsedMinimum
    draft.maximumAmountMinor = parsedMaximum
    filters = draft
    dismiss()
  }
}
