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
  @State private var minimumMinor: Int64
  @State private var maximumMinor: Int64

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
    _minimumMinor = State(initialValue: current.minimumAmountMinor ?? 0)
    _maximumMinor = State(initialValue: current.maximumAmountMinor ?? 0)
  }

  private var parsedMinimum: Int64? { minimumMinor > 0 ? minimumMinor : nil }
  private var parsedMaximum: Int64? { maximumMinor > 0 ? maximumMinor : nil }

  private var canApply: Bool {
    let amountRangeIsValid: Bool
    if let parsedMinimum, let parsedMaximum {
      amountRangeIsValid = parsedMinimum <= parsedMaximum
    } else {
      amountRangeIsValid = true
    }
    let dateRangeIsValid = !usesStartDate || !usesEndDate
      || Calendar.current.compare(startDate, to: endDate, toGranularity: .day)
        != .orderedDescending
    return amountRangeIsValid && dateRangeIsValid
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
          CurrencyAmountField("Minimum", minor: $minimumMinor, currencyCode: currencyCode)
          CurrencyAmountField("Maximum", minor: $maximumMinor, currencyCode: currencyCode)
        } header: {
          Text("Amount (\(currencyCode))")
        } footer: {
          Text("Leave at zero for no limit. Outflows are filtered by their absolute value.")
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
