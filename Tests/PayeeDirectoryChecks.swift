import Foundation

@main
struct PayeeDirectoryChecks {
  static func main() {
    let envelopeID = UUID()
    let payee = BudgetPayee(
      name: "City Market",
      defaultEnvelopeID: envelopeID,
      exactMatchText: "CITY MARKET STORE"
    )
    let first = BudgetTransaction(
      accountID: UUID(),
      date: Date(),
      amountMinor: -2_500,
      payee: "City Market",
      notes: "",
      kind: .expense
    )
    let imported = BudgetTransaction(
      accountID: first.accountID,
      date: Date(),
      amountMinor: -1_200,
      payee: "CITY MARKET STORE",
      notes: "",
      kind: .expense
    )
    let scheduled = BudgetSchedule(
      payee: "City Market",
      amountMinor: 3_000,
      accountID: first.accountID,
      envelopeID: envelopeID,
      startDate: Date(),
      frequency: .monthly,
      notes: ""
    )
    let entries = PayeeDirectory.entries(
      payees: [payee], transactions: [first, imported], schedules: [scheduled]
    )
    precondition(entries.count == 1)
    precondition(entries[0].transactionCount == 2)
    precondition(entries[0].scheduleCount == 1)

    let matcher = PayeeRuleMatcher()
    let rules = PayeeDirectory.ruleItems(payees: [payee], validEnvelopeIDs: [envelopeID])
    precondition(matcher.envelopeID(for: "city market", rules: rules) == envelopeID)
    precondition(matcher.envelopeID(for: "CITY MARKET STORE", rules: rules) == envelopeID)

    PayeeDirectory.rename(
      from: entries[0].key,
      to: "Neighborhood Market",
      payees: [payee],
      transactions: [first, imported],
      schedules: [scheduled]
    )
    precondition(first.payee == "Neighborhood Market")
    precondition(imported.payee == "Neighborhood Market")
    precondition(scheduled.payee == "Neighborhood Market")
    print("Payee directory checks passed")
  }
}
