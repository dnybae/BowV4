import Foundation

@main
struct PayeeDirectoryChecks {
  static func main() {
    let envelopeID = UUID()
    let payee = BudgetPayee(
      name: "City Market",
      defaultEnvelopeID: envelopeID,
      exactMatchText: "CITY MARKET STORE",
      merchantDomain: "citymarket.example"
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
    precondition(PayeeDirectory.matchingPayee(for: "CITY MARKET STORE", payees: [payee]) === payee)
    precondition(PayeeDirectory.logoDomain(
      for: imported.payee, transactionDomain: nil, payees: [payee]
    ) == "citymarket.example")
    payee.merchantDomain = nil
    precondition(PayeeDirectory.logoDomain(
      for: imported.payee, transactionDomain: "wrong.example", payees: [payee]
    ) == nil)

    let matcher = PayeeRuleMatcher()
    let rules = PayeeDirectory.ruleItems(payees: [payee], validEnvelopeIDs: [envelopeID])
    precondition(matcher.envelopeID(for: "city market", rules: rules) == envelopeID)
    precondition(matcher.envelopeID(for: "CITY MARKET STORE", rules: rules) == envelopeID)

    // The original single bank description folds into the bank names list.
    precondition(payee.bankNames == ["CITY MARKET STORE"])
    payee.bankNames = ["CITY MARKET STORE", "city market store ", "CITYMKT #42", "City Market", ""]
    precondition(payee.bankNames == ["CITY MARKET STORE", "CITYMKT #42"])
    precondition(payee.exactMatchText.isEmpty)
    precondition(PayeeDirectory.matchingPayee(for: "citymkt #42", payees: [payee]) === payee)
    precondition(PayeeDirectory.canonicalKey(for: "CITYMKT #42", payees: [payee]) == PayeeDirectory.key("City Market"))
    let extraRules = PayeeDirectory.ruleItems(payees: [payee], validEnvelopeIDs: [envelopeID])
    precondition(matcher.envelopeID(for: "CITYMKT #42", rules: extraRules) == envelopeID)
    precondition(PayeeDirectory.aliases(for: [payee])[PayeeDirectory.key("CITYMKT #42")] == PayeeDirectory.key("City Market"))

    // Scheduled bills match bank text through saved bank names.
    precondition(PayeeDirectory.isSamePayee("City Market", "CITYMKT #42", payees: [payee]))
    precondition(PayeeDirectory.isSamePayee("city market", "City Market", payees: []))
    precondition(!PayeeDirectory.isSamePayee("City Market", "Corner Store", payees: [payee]))
    precondition(!PayeeDirectory.isSamePayee("", "", payees: [payee]))

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
