import Foundation
import SwiftData

@MainActor
enum DemoData {
  static var sampleYNABExport: String {
    "Category Group,Category\nLearning,Books\nLearning,Courses\nGiving,Charity\nGiving,Community Events\n"
  }

  static var sampleBankCSV: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM/dd/yyyy"
    let today = Date()
    let recent = Calendar.current.date(byAdding: .day, value: -2, to: today) ?? today
    return "Date,Payee,Memo,Amount\n"
      + "\(formatter.string(from: recent)),The Home Depot,New expense,-49.99\n"
      + "\(formatter.string(from: today)),Target,Refund,12.00\n"
      + "\(formatter.string(from: today)),Netflix,Possible duplicate,-15.99\n"
  }

  static func makeContainer(scenario: DemoScenario = .showcase) throws -> ModelContainer {
    let schema = Schema([
      BudgetProfile.self,
      BudgetAccount.self,
      BudgetGroup.self,
      BudgetEnvelope.self,
      BudgetTransaction.self,
      BudgetAllocation.self,
      BudgetPayee.self,
      BudgetSchedule.self,
      BudgetScheduleOccurrence.self,
      SimpleFINConnection.self,
      SimpleFINAccountLink.self,
      SimpleFINImportRecord.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: configuration)
    try seed(scenario: scenario, in: container.mainContext)
    return container
  }

  private static func seed(scenario: DemoScenario, in context: ModelContext) throws {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
    let currentDay = calendar.component(.day, from: today)
    func date(_ monthOffset: Int, _ day: Int) -> Date {
      let month = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) ?? currentMonth
      let finalDay = monthOffset == 0 ? min(day, currentDay) : day
      return calendar.date(byAdding: .day, value: finalDay - 1, to: month) ?? month
    }
    @discardableResult
    func insert<T: PersistentModel>(_ model: T) -> T {
      context.insert(model)
      return model
    }

    insert(BudgetProfile(currencyCode: "USD"))
    if scenario == .empty {
      try context.save()
      return
    }

    let everyday = insert(BudgetAccount(name: "Everyday Checking", kind: .cash, currencyCode: "USD", openingBalanceMinor: 185_000))
    let savings = insert(BudgetAccount(name: "High-Yield Savings", kind: .cash, currencyCode: "USD", openingBalanceMinor: 375_000))
    let wallet = insert(BudgetAccount(name: "Cash Wallet", kind: .cash, currencyCode: "USD", openingBalanceMinor: 8_000))
    let card = insert(BudgetAccount(name: "Travel Card", kind: .credit, currencyCode: "USD", openingBalanceMinor: -92_000))
    let floatingCard = insert(BudgetAccount(name: "Everyday Rewards", kind: .credit, currencyCode: "USD", openingBalanceMinor: 0))
    let investments = insert(BudgetAccount(name: "Investment Account", kind: .asset, currencyCode: "USD", openingBalanceMinor: 640_000))
    let loan = insert(BudgetAccount(name: "Auto Loan", kind: .liability, currencyCode: "USD", openingBalanceMinor: -520_000))
    for account in [everyday, savings, wallet, card, floatingCard, investments, loan] {
      account.openedAt = date(-7, 1)
    }
    savings.lastReconciledAt = date(-1, 28)
    savings.lastReconciledBalanceMinor = 410_000

    let essentials = insert(BudgetGroup(name: "Essentials", sortOrder: 0))
    let lifestyle = insert(BudgetGroup(name: "Everyday Life", sortOrder: 1))
    let future = insert(BudgetGroup(name: "Future & Debt", sortOrder: 2))
    func envelope(_ name: String, _ symbol: String, _ group: BudgetGroup, _ order: Int, _ target: Int64?) -> BudgetEnvelope {
      let item = insert(BudgetEnvelope(groupID: group.id, name: name, symbol: symbol, sortOrder: order))
      item.targetMinor = target
      return item
    }
    let housing = envelope("Rent", "house.fill", essentials, 0, 145_000)
    let groceries = envelope("Groceries", "cart.fill", essentials, 1, 48_000)
    let utilities = envelope("Utilities", "bolt.fill", essentials, 2, 24_000)
    let transport = envelope("Transportation", "car.fill", essentials, 3, 22_000)
    let dining = envelope("Dining Out", "fork.knife", lifestyle, 0, 16_000)
    let fun = envelope("Fun & Hobbies", "sparkles", lifestyle, 1, 10_000)
    let health = envelope("Medical", "cross.case.fill", lifestyle, 2, 12_000)
    let travel = envelope("Travel", "airplane", lifestyle, 3, 35_000)
    let emergency = envelope("Emergency Fund", "shield.fill", future, 0, 100_000)
    let carPayment = envelope("Car Payment", "car.side.fill", future, 1, 32_000)
    let gifts = envelope("Gifts", "gift.fill", future, 2, nil)

    func allocate(_ amount: Int64, to target: BudgetEnvelope, in month: Int) {
      insert(BudgetAllocation(date: date(month, 2), amountMinor: amount, targetEnvelopeID: target.id))
    }
    @discardableResult
    func transaction(
      _ payee: String, _ amount: Int64, _ kind: BudgetTransactionKind,
      from account: BudgetAccount, to destination: BudgetAccount? = nil,
      envelope category: BudgetEnvelope? = nil, month: Int = 0, day: Int,
      notes: String = "", domain: String? = nil, cleared: Bool = true
    ) -> BudgetTransaction {
      let item = insert(BudgetTransaction(
        accountID: account.id,
        transferAccountID: destination?.id,
        envelopeID: category?.id,
        date: date(month, day),
        amountMinor: amount,
        payee: payee,
        merchantDomain: domain,
        notes: notes,
        kind: kind
      ))
      item.isCleared = cleared
      item.destinationIsCleared = cleared && destination != nil
      return item
    }

    var previousRent: BudgetTransaction?
    for month in -5...0 {
      transaction("Paycheck", 465_000, .inflow, from: everyday, month: month, day: 1, notes: "Twice-monthly salary combined")
      let rent = transaction("Apartment Rent", -145_000, .expense, from: everyday, envelope: housing, month: month, day: 3)
      if month == -1 { previousRent = rent }
      transaction("Whole Foods Market", month == 0 ? -52_480 : -32_000 - Int64((month + 5) * 1_500), .expense, from: everyday, envelope: groceries, month: month, day: 7, domain: "wholefoodsmarket.com")
      transaction("ComEd", -18_500, .expense, from: everyday, envelope: utilities, month: month, day: 11, domain: "comed.com")
      transaction("Uber", -12_000, .expense, from: everyday, envelope: transport, month: month, day: 13, domain: "uber.com")
      transaction("Starbucks", -780, .expense, from: card, envelope: dining, month: month, day: 16, domain: "starbucks.com")
      transaction("Card Payment", -20_000, .transfer, from: everyday, to: card, month: month, day: 19)
      allocate(145_000, to: housing, in: month)
      allocate(month == 0 ? 36_000 : 48_000, to: groceries, in: month)
      allocate(24_000, to: utilities, in: month)
      allocate(22_000, to: transport, in: month)
      allocate(16_000, to: dining, in: month)
      allocate(10_000, to: fun, in: month)
      allocate(12_000, to: health, in: month)
      allocate(20_000, to: travel, in: month)
      allocate(18_000, to: emergency, in: month)
      allocate(32_000, to: carPayment, in: month)
    }

    transaction("Starting bonus", 75_000, .inflow, from: everyday, month: -4, day: 22)
    transaction("Hilton", -26_000, .expense, from: card, envelope: travel, month: -3, day: 23, domain: "hilton.com")
    transaction("Aspen Dental", -9_500, .expense, from: everyday, envelope: health, month: -2, day: 21, domain: "aspendental.com")
    transaction("Reimbursement", 4_200, .inflow, from: everyday, envelope: health, month: -2, day: 25)
    transaction("Savings Transfer", -35_000, .transfer, from: everyday, to: savings, month: -1, day: 25)
    transaction("Car Loan Payment", -31_500, .transfer, from: everyday, to: loan, envelope: carPayment, month: -1, day: 26)
    transaction("Investing", -20_000, .transfer, from: everyday, to: investments, envelope: emergency, month: -1, day: 27)
    transaction("Macy’s", -42_000, .expense, from: floatingCard, envelope: gifts, month: -1, day: 20, domain: "macys.com")
    transaction("Rewards Card Payment", -5_000, .transfer, from: everyday, to: floatingCard, month: 0, day: 14)
    let gift = transaction("Target", -5_800, .expense, from: wallet, envelope: gifts, month: 0, day: 12, domain: "target.com", cleared: false)
    gift.notes = "Cash purchase to fund"
    transaction("Olive Garden", -18_500, .expense, from: card, envelope: dining, month: 0, day: 17, domain: "olivegarden.com", cleared: false)
    transaction("CVS Pharmacy", -4_600, .expense, from: everyday, envelope: health, month: 0, day: 18, domain: "cvs.com")
    transaction("Netflix", -1_599, .expense, from: card, envelope: fun, day: 21, domain: "netflix.com")
    let match = transaction("Whole Foods Market", -3_200, .expense, from: everyday, envelope: groceries, day: 22, domain: "wholefoodsmarket.com", cleared: false)
    match.notes = "Manually entered before bank import"
    let linked = transaction("Dunkin", -650, .expense, from: everyday, envelope: dining, day: 23, domain: "dunkindonuts.com", cleared: false)
    let linkedSnapshot = try JSONEncoder().encode(ManualTransactionSnapshot(linked))
    linked.sourceRaw = "manualLinked"
    linked.externalKey = "demo|coffee"
    linked.isCleared = true
    let imported = transaction("Barnes & Noble", -2_400, .expense, from: card, envelope: fun, day: 24, domain: "barnesandnoble.com")
    imported.sourceRaw = "simplefin"
    imported.externalKey = "demo|bookstore"
    imported.needsApproval = false

    insert(BudgetPayee(name: "Whole Foods Market", defaultEnvelopeID: groceries.id, exactMatchText: "WHOLE FOODS", merchantDomain: "wholefoodsmarket.com"))
    insert(BudgetPayee(name: "Apartment Rent", defaultEnvelopeID: housing.id, exactMatchText: "APARTMENT RENT ACH"))
    insert(BudgetPayee(name: "Starbucks", defaultEnvelopeID: dining.id, exactMatchText: "STARBUCKS", merchantDomain: "starbucks.com"))
    insert(BudgetPayee(name: "Netflix", defaultEnvelopeID: fun.id, exactMatchText: "NETFLIX", merchantDomain: "netflix.com"))

    let rentSchedule = insert(BudgetSchedule(payee: "Apartment Rent", amountMinor: 145_000, accountID: everyday.id, envelopeID: housing.id, startDate: date(-5, 3), frequency: .monthly, notes: "Due on the 3rd"))
    previousRent?.scheduleID = rentSchedule.id
    previousRent?.scheduledFor = date(-1, 3)
    insert(BudgetSchedule(payee: "Instacart", amountMinor: 13_000, accountID: everyday.id, envelopeID: groceries.id, startDate: today, frequency: .weekly, notes: "Weekly grocery order"))
    insert(BudgetSchedule(payee: "GEICO", amountMinor: 28_000, accountID: everyday.id, envelopeID: transport.id, startDate: today, frequency: .once, notes: "Auto insurance"))
    insert(BudgetSchedule(payee: "Disney+", amountMinor: 12_000, accountID: card.id, envelopeID: fun.id, startDate: date(-2, 18), frequency: .yearly, notes: "Renews annually"))
    let paused = insert(BudgetSchedule(payee: "Planet Fitness", amountMinor: 4_500, accountID: everyday.id, envelopeID: fun.id, startDate: date(-1, 8), frequency: .monthly, notes: "Inactive example"))
    paused.isActive = false

    let connection = insert(SimpleFINConnection())
    connection.lastSuccessfulAt = Date().addingTimeInterval(-3_600)
    connection.lastAttemptAt = connection.lastSuccessfulAt
    connection.automaticSync = false
    connection.lastMessage = nil
    let checkingLink = insert(SimpleFINAccountLink(remoteKey: "demo-checking", name: "Example Bank Checking", currencyCode: "USD"))
    checkingLink.localAccountID = everyday.id
    checkingLink.reportedBalance = "3850.20"
    checkingLink.reportedAt = today
    let cardLink = insert(SimpleFINAccountLink(remoteKey: "demo-card", name: "Example Bank Card", currencyCode: "USD"))
    cardLink.localAccountID = card.id
    cardLink.reportedBalance = "-520.64"
    cardLink.reportedAt = today
    let availableLink = insert(SimpleFINAccountLink(remoteKey: "demo-savings", name: "Example Bank Savings", currencyCode: "USD"))
    availableLink.reportedBalance = "1250.00"
    availableLink.reportedAt = today

    let duplicate = insert(SimpleFINImportRecord(remoteKey: "demo|duplicate", localAccountID: everyday.id, date: match.date, amountMinor: -3_200, payee: "Whole Foods Market"))
    duplicate.status = .review
    let unmatched = insert(SimpleFINImportRecord(remoteKey: "demo|unmatched", localAccountID: card.id, date: today, amountMinor: -8_750, payee: "Delta Air Lines"))
    unmatched.status = .review
    let linkedRecord = insert(SimpleFINImportRecord(remoteKey: "demo|coffee", localAccountID: everyday.id, date: linked.date, amountMinor: linked.amountMinor, payee: linked.payee))
    linkedRecord.status = .linked
    linkedRecord.transactionID = linked.id
    linkedRecord.matchedAutomatically = true
    linkedRecord.originalManualSnapshot = linkedSnapshot
    let importedRecord = insert(SimpleFINImportRecord(remoteKey: "demo|bookstore", localAccountID: card.id, date: imported.date, amountMinor: imported.amountMinor, payee: imported.payee))
    importedRecord.status = .imported
    importedRecord.transactionID = imported.id
    let ignoredRecord = insert(SimpleFINImportRecord(remoteKey: "demo|ignored", localAccountID: everyday.id, date: date(0, 15), amountMinor: -1_200, payee: "Duplicate Parking"))
    ignoredRecord.status = .ignored
    let pendingBank = insert(SimpleFINImportRecord(remoteKey: "demo|pending", localAccountID: everyday.id, date: today, amountMinor: -1_850, payee: "Blue Bottle Coffee"))
    pendingBank.bankState = .pending
    pendingBank.isVisiblePending = true
    pendingBank.lastSeenAt = today

    if scenario == .deficit {
      insert(BudgetAllocation(date: today, amountMinor: 1_500_000, targetEnvelopeID: emergency.id))
    }

    try BudgetCommands.ensureCardPaymentEnvelopes(in: context)

    try context.save()
  }
}
