import Foundation

@main
struct BankTransactionMatcherChecks {
  static func main() {
    let accountID = UUID()
    let otherAccountID = UUID()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let manualID = UUID()
    let incoming = BankTransactionCandidate(
      externalKey: "connection/account/transaction-1",
      accountID: accountID,
      amountMinor: -2_548,
      postedAt: date.addingTimeInterval(2 * 24 * 60 * 60),
      transactedAt: date,
      description: "Corner Cafe"
    )
    let manual = LocalTransactionCandidate(
      id: manualID,
      accountID: accountID,
      amountMinor: -2_548,
      date: date,
      payee: "Corner Café",
      externalKey: nil,
      isManual: true
    )
    let matcher = BankTransactionMatcher()
    precondition(matcher.decide(for: incoming, among: [manual]) == .linkManual(manualID))

    var alreadyLinked = manual
    alreadyLinked.externalKey = incoming.externalKey
    precondition(matcher.decide(for: incoming, among: [alreadyLinked]) == .alreadyImported(manualID))

    var amountChanged = manual
    amountChanged.amountMinor = -2_848
    precondition(matcher.decide(for: incoming, among: [amountChanged]) == .review([manualID]))

    var wrongAccount = manual
    wrongAccount.accountID = otherAccountID
    precondition(matcher.decide(for: incoming, among: [wrongAccount]) == .createNew)

    var secondManual = manual
    secondManual.id = UUID()
    precondition(
      matcher.decide(for: incoming, among: [manual, secondManual])
        == .review([manualID, secondManual.id])
    )
    print("Bank transaction matcher checks passed")
  }
}
