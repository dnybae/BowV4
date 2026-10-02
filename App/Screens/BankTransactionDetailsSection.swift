import SwiftUI

/// Original imported values, kept separate from the user's editable transaction fields.
struct BankTransactionDetailsSection: View {
  var record: SimpleFINImportRecord
  var accountName: String
  var currencyCode: String

  var body: some View {
    Section {
      detail("Payee", value: record.payee.isEmpty ? "Not provided" : record.payee)
      detail("Amount", value: BudgetMoney.formatted(record.amountMinor, currencyCode: currencyCode))
      detail("Date", value: record.date.formatted(date: .abbreviated, time: .omitted))
      detail("Account", value: accountName)
      detail("Status", value: record.bankState == .pending ? "Pending" : "Posted")
      if !record.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        detail("Bank memo", value: record.memo)
      }
    } header: {
      Text("From your bank")
    } footer: {
      Text("Original details from \(record.origin == .bankFile ? "your bank file" : "bank sync"). Editing this transaction keeps these details unchanged.")
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }

  private func detail(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: Bow.Space.s1) {
      Text(title)
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
      Text(value)
        .foregroundStyle(Bow.ink)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
