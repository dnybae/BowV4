import Foundation

@main
struct TransactionFilterChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func day(_ value: Int, hour: Int = 12) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 9, day: value, hour: hour))!
    }

    let cashID = UUID()
    let savingsID = UUID()
    let groceriesID = UUID()
    let purchase = TransactionFilterItem(
      accountID: cashID,
      transferAccountID: nil,
      envelopeID: groceriesID,
      date: day(15, hour: 23),
      amountMinor: -2_500,
      isUncategorizedExpense: false
    )

    var filter = TransactionFilter(
      accountID: cashID,
      envelopeScope: .envelope(groceriesID),
      startDate: day(15, hour: 0),
      endDate: day(15, hour: 0),
      minimumAmountMinor: 2_000,
      maximumAmountMinor: 3_000
    )
    precondition(filter.activeCount == 6)
    precondition(filter.includes(purchase, calendar: calendar), "date endpoints include the whole day")

    filter.maximumAmountMinor = 2_499
    precondition(!filter.includes(purchase, calendar: calendar), "outflows use absolute amount")
    filter.maximumAmountMinor = nil
    filter.endDate = day(14)
    precondition(!filter.includes(purchase, calendar: calendar), "dates after the range are excluded")

    filter = TransactionFilter(accountID: savingsID)
    var transfer = purchase
    transfer.transferAccountID = savingsID
    precondition(filter.includes(transfer, calendar: calendar), "destination account includes transfers")

    filter = TransactionFilter(envelopeScope: .uncategorized)
    var uncategorized = purchase
    uncategorized.envelopeID = nil
    uncategorized.isUncategorizedExpense = true
    precondition(filter.includes(uncategorized, calendar: calendar))
    uncategorized.isUncategorizedExpense = false
    precondition(!filter.includes(uncategorized, calendar: calendar), "transfers are not uncategorized expenses")
    filter = TransactionFilter(needsApprovalOnly: true)
    precondition(!filter.includes(purchase, calendar: calendar))
    var imported = purchase
    imported.needsApproval = true
    precondition(filter.includes(imported, calendar: calendar))
    print("Transaction filter checks passed")
  }
}
