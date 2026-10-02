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
        Section {
          BowIdentityHeader(name: "Filter transactions", systemImage: "line.3.horizontal.decrease")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section("Show") {
          Picker("Show", selection: $draft.status) {
            ForEach(TransactionStatusScope.allCases, id: \.self) { status in
              Text(status.title).tag(status)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        Section {
          AccountSelectionField(
            title: "Account", selection: $draft.accountID,
            accounts: accounts, noneTitle: "All accounts", systemImage: "building.columns"
          )
          EnvelopeScopeSelectionField(selection: $draft.envelopeScope, envelopes: envelopes,
                                      systemImage: "square.grid.2x2")
        }
        .listRowBackground(Bow.card)

        Section("Dates") {
          Toggle(isOn: $usesStartDate) {
            Label("From a date", systemImage: "calendar").labelStyle(.bowTile)
          }
          if usesStartDate {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
              .datePickerStyle(.compact)
          }
          Toggle(isOn: $usesEndDate) {
            Label("Through a date", systemImage: "calendar").labelStyle(.bowTile)
          }
          if usesEndDate {
            DatePicker("Through", selection: $endDate, displayedComponents: .date)
              .datePickerStyle(.compact)
          }
        }
        .listRowBackground(Bow.card)

        Section {
          CurrencyAmountField("At least", minor: $minimumMinor, currencyCode: currencyCode,
                              systemImage: "dollarsign")
          CurrencyAmountField("At most", minor: $maximumMinor, currencyCode: currencyCode,
                              systemImage: "dollarsign")
        } header: {
          Text("Amount")
        } footer: {
          Text("Leave at zero for no limit. Outflows are compared by their size, so “at least 50” finds −50 and up.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)

        Section {
          Button("Clear all filters") {
            filters = TransactionFilter()
            dismiss()
          }
        }
        .listRowBackground(Bow.card)
      }
      .bowSkyList(mood: .dawn, height: 420)
      .navigationTitle("Filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Cancel") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button { apply() } label: { BowToolbarLabel("Apply") }
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
