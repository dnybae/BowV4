import Foundation
import SwiftData

@MainActor @main
struct DemoDataChecks {
  static func main() throws {
    let sample = try DemoData.makeContainer()
    let sampleContext = sample.mainContext
    let profiles = try sampleContext.fetch(FetchDescriptor<BudgetProfile>())
    let accounts = try sampleContext.fetch(FetchDescriptor<BudgetAccount>())
    let envelopes = try sampleContext.fetch(FetchDescriptor<BudgetEnvelope>())
    let transactions = try sampleContext.fetch(FetchDescriptor<BudgetTransaction>())
    let allocations = try sampleContext.fetch(FetchDescriptor<BudgetAllocation>())
    let schedules = try sampleContext.fetch(FetchDescriptor<BudgetSchedule>())
    let rules = try sampleContext.fetch(FetchDescriptor<BudgetPayee>())
    let reviews = try sampleContext.fetch(FetchDescriptor<SimpleFINImportRecord>())
    expect(profiles.count == 1, "sample budget opens without onboarding")
    expect(Set(accounts.map(\.kind)) == Set(BudgetAccountKind.allCases), "every account kind is present")
    expect(transactions.contains { $0.kind == .transfer }, "transfers are present")
    expect(transactions.contains { $0.kind == .inflow }, "income is present")
    expect(!transactions.contains { $0.envelopeID == nil && $0.kind == .expense },
           "sample ledger contains no uncategorized expenses")
    expect(!transactions.contains { $0.sourceRaw == "simplefin" && $0.needsApproval },
           "SimpleFIN posted review items are held outside the ledger")
    expect(Set(schedules.map(\.frequency)) == Set(ScheduleFrequency.allCases), "every recurrence is present")
    expect(schedules.contains { !$0.isActive }, "paused schedule is present")
    expect(!rules.isEmpty, "payee rules are present")
    expect(reviews.filter { $0.bankState == .posted && $0.status == .review }.count == 2,
           "bank review has matching and unmatched rows")
    expect(reviews.filter { $0.bankState == .pending && $0.isVisiblePending }.count == 1,
           "pending authorizations have their own section")
    expect(reviews.contains { $0.status == .linked && $0.matchedAutomatically },
           "the sample includes an automatic match with provenance")

    let snapshot = BudgetLedger.snapshot(
      month: Date(), accounts: accounts, envelopes: envelopes,
      allocations: allocations, transactions: transactions
    )
    expect(snapshot.cashShortfall.values.contains { $0 > 0 }, "sample has cash overspending")
    expect(!snapshot.paymentAvailable.isEmpty, "sample has credit card payment data")

    let empty = try DemoData.makeContainer(scenario: .empty)
    let emptyProfiles = try empty.mainContext.fetchCount(FetchDescriptor<BudgetProfile>())
    let emptyAccounts = try empty.mainContext.fetchCount(FetchDescriptor<BudgetAccount>())
    let emptyTransactions = try empty.mainContext.fetchCount(FetchDescriptor<BudgetTransaction>())
    expect(emptyProfiles == 1, "empty situation has a budget")
    expect(emptyAccounts == 0, "empty situation has no accounts")
    expect(emptyTransactions == 0, "empty situation has no activity")

    let deficit = try DemoData.makeContainer(scenario: .deficit)
    let deficitContext = deficit.mainContext
    let deficitSnapshot = BudgetLedger.snapshot(
      month: Date(),
      accounts: try deficitContext.fetch(FetchDescriptor<BudgetAccount>()),
      envelopes: try deficitContext.fetch(FetchDescriptor<BudgetEnvelope>()),
      allocations: try deficitContext.fetch(FetchDescriptor<BudgetAllocation>()),
      transactions: try deficitContext.fetch(FetchDescriptor<BudgetTransaction>())
    )
    expect(deficitSnapshot.readyToAssignMinor < 0, "cash shortfall situation has negative Ready to Assign")

    let bankParser = BankFileParser()
    let bankTable = try bankParser.csvTable(DemoData.sampleBankCSV)
    let bankRows = try bankParser.csvRows(bankTable, mapping: BankCSVMapping.suggested(for: bankTable.headers))
    expect(bankRows.count == 3, "sample bank CSV can be previewed")
    let ynab = try YNABCategoryParser().parse(DemoData.sampleYNABExport)
    expect(ynab.groups.count == 2 && ynab.envelopeCount == 4, "sample YNAB export can be previewed")
    print("Demo data checks passed")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
