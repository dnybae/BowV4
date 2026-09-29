import Foundation

@main
struct BankImportPlannerChecks {
  static func main() {
    let accountID = UUID()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let manualID = UUID()
    let manual = LocalTransactionCandidate(
      id: manualID,
      accountID: accountID,
      amountMinor: -1_548,
      date: date,
      payee: "Corner Cafe",
      externalKey: nil,
      isManual: true
    )
    let row = BankImportRow(
      rowNumber: 1,
      date: date,
      amountMinor: -1_548,
      payee: "Corner Cafe",
      memo: "Lunch",
      externalID: "FIT-1"
    )
    let planner = BankImportPlanner()
    let first = planner.plan(rows: [row], accountID: accountID, existing: [manual])
    precondition(first.count == 1)
    precondition(first[0].decision == .linkManual(manualID))

    var linked = manual
    linked.externalKey = first[0].externalKey
    linked.isManual = false
    let repeated = planner.plan(rows: [row], accountID: accountID, existing: [linked])
    precondition(repeated[0].decision == .alreadyImported(manualID))

    var transfer = manual
    transfer.payee = "Transfer"
    let held = planner.plan(rows: [row], accountID: accountID, existing: [], manualTransfers: [transfer])
    precondition(held[0].decision == .review([manualID]))

    var otherFile = manual
    otherFile.externalKey = "file-from-another-export"
    otherFile.isManual = false
    let overlapping = planner.plan(rows: [row], accountID: accountID, existing: [otherFile])
    precondition(overlapping[0].decision == .review([manualID]))
    let scaleStart = ContinuousClock.now
    let historical = (0..<50_000).map { index in
      LocalTransactionCandidate(
        id: UUID(), accountID: accountID,
        amountMinor: -Int64(100 + index),
        date: date.addingTimeInterval(TimeInterval(index % 3_650) * 86_400),
        payee: "Historical \(index)", externalKey: nil, isManual: true
      )
    }
    let imported = (0..<2_000).map { index in
      BankImportRow(
        rowNumber: index + 1,
        date: date.addingTimeInterval(TimeInterval(index % 3_650) * 86_400),
        amountMinor: -Int64(100_000 + index), payee: "New \(index)",
        memo: "", externalID: "SCALE-\(index)"
      )
    }
    let scaleResult = planner.plan(rows: imported, accountID: accountID, existing: historical)
    precondition(scaleResult.count == imported.count)
    precondition(scaleResult.allSatisfy { $0.decision == .createNew })
    print("50,000 local candidates and 2,000 import rows planned in \(ContinuousClock.now - scaleStart)")
    print("Bank import planner checks passed")
  }
}
