import Foundation

@main
struct SimpleFINMatchPlannerChecks {
  static func main() {
    let accountID = UUID()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let manual = LocalTransactionCandidate(
      id: UUID(), accountID: accountID, amountMinor: -2_548,
      date: date, payee: "Cafe", externalKey: nil, isManual: true
    )
    let incoming = BankTransactionCandidate(
      externalKey: "simplefin|account|transaction", accountID: accountID,
      amountMinor: -2_548, postedAt: date.addingTimeInterval(8 * 86_400),
      transactedAt: nil, description: "Different bank payee"
    )
    let planner = SimpleFINMatchPlanner()
    precondition(planner.decide(for: incoming, among: [manual]) == .linkManual(manual.id))

    var repeatedAmount = manual
    repeatedAmount.id = UUID()
    precondition(planner.decide(for: incoming, among: [manual, repeatedAmount])
      == .review([manual.id, repeatedAmount.id]))

    var wrongAccount = manual
    wrongAccount.accountID = UUID()
    precondition(planner.decide(for: incoming, among: [wrongAccount]) == .createNew)

    var old = manual
    old.date = date.addingTimeInterval(-4 * 86_400)
    precondition(planner.decide(for: incoming, among: [old]) == .createNew)

    var alreadyImported = manual
    alreadyImported.externalKey = incoming.externalKey
    alreadyImported.isManual = false
    precondition(planner.decide(for: incoming, among: [alreadyImported])
      == .alreadyImported(manual.id))
    print("SimpleFIN matching checks passed")
  }
}
