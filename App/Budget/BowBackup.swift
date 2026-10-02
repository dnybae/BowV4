import Foundation
import SwiftData

/// Everything in a budget as one JSON file: Settings › Export data writes it, and Restore from
/// backup replaces the budget with it. Bank sync credentials live in the Keychain and are never
/// included, so a restored budget reconnects to SimpleFIN separately.
struct BowBackup: Codable {
  static let currentFormat = 1

  var format: Int
  var exportedAt: Date
  var appVersion: String
  var profile: Profile?
  var accounts: [Account]
  var groups: [Group]
  var envelopes: [Envelope]
  var transactions: [Transaction]
  var allocations: [Allocation]
  var payees: [Payee]
  var schedules: [Schedule]
  var occurrences: [Occurrence]
  var bankLinks: [BankLink]
  var bankRecords: [BankRecord]

  enum RestoreError: LocalizedError {
    case newerFormat
    case noBudget

    var errorDescription: String? {
      switch self {
      case .newerFormat: "This backup was made by a newer version of Bow. Update Bow, then try again."
      case .noBudget: "This file doesn’t contain a Bow budget."
      }
    }
  }

  // MARK: - Export

  static func make(from context: ModelContext, appVersion: String) throws -> BowBackup {
    BowBackup(
      format: currentFormat,
      exportedAt: Date(),
      appVersion: appVersion,
      profile: try context.fetch(FetchDescriptor<BudgetProfile>()).first.map(Profile.init),
      accounts: try context.fetch(FetchDescriptor<BudgetAccount>()).map(Account.init),
      groups: try context.fetch(FetchDescriptor<BudgetGroup>()).map(Group.init),
      envelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()).map(Envelope.init),
      transactions: try context.fetch(FetchDescriptor<BudgetTransaction>()).map(Transaction.init),
      allocations: try context.fetch(FetchDescriptor<BudgetAllocation>()).map(Allocation.init),
      payees: try context.fetch(FetchDescriptor<BudgetPayee>()).map(Payee.init),
      schedules: try context.fetch(FetchDescriptor<BudgetSchedule>()).map(Schedule.init),
      occurrences: try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>()).map(Occurrence.init),
      bankLinks: try context.fetch(FetchDescriptor<SimpleFINAccountLink>()).map(BankLink.init),
      bankRecords: try context.fetch(FetchDescriptor<SimpleFINImportRecord>()).map(BankRecord.init)
    )
  }

  static func decode(_ data: Data) throws -> BowBackup {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let backup = try decoder.decode(BowBackup.self, from: data)
    guard backup.format <= currentFormat else { throw RestoreError.newerFormat }
    guard backup.profile != nil else { throw RestoreError.noBudget }
    return backup
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  // MARK: - Restore

  /// Replaces everything in the budget with this backup, in a single save.
  func restore(into context: ModelContext) throws {
    try Self.deleteAll(BudgetProfile.self, in: context)
    try Self.deleteAll(BudgetAccount.self, in: context)
    try Self.deleteAll(BudgetGroup.self, in: context)
    try Self.deleteAll(BudgetEnvelope.self, in: context)
    try Self.deleteAll(BudgetTransaction.self, in: context)
    try Self.deleteAll(BudgetAllocation.self, in: context)
    try Self.deleteAll(BudgetPayee.self, in: context)
    try Self.deleteAll(BudgetSchedule.self, in: context)
    try Self.deleteAll(BudgetScheduleOccurrence.self, in: context)
    try Self.deleteAll(SimpleFINAccountLink.self, in: context)
    try Self.deleteAll(SimpleFINImportRecord.self, in: context)
    try Self.deleteAll(SimpleFINConnection.self, in: context)

    if let profile { context.insert(profile.model) }
    accounts.forEach { context.insert($0.model) }
    groups.forEach { context.insert($0.model) }
    envelopes.forEach { context.insert($0.model) }
    transactions.forEach { context.insert($0.model) }
    allocations.forEach { context.insert($0.model) }
    payees.forEach { context.insert($0.model) }
    schedules.forEach { context.insert($0.model) }
    occurrences.forEach { context.insert($0.model) }
    bankLinks.forEach { context.insert($0.model) }
    bankRecords.forEach { context.insert($0.model) }
    try context.save()
  }

  private static func deleteAll<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) throws {
    for item in try context.fetch(FetchDescriptor<Model>()) { context.delete(item) }
  }

  /// A one-line description for the restore confirmation.
  var summary: String {
    let accountText = accounts.count == 1 ? "1 account" : "\(accounts.count) accounts"
    let transactionText = transactions.count == 1 ? "1 transaction" : "\(transactions.count.formatted()) transactions"
    return "\(profile?.name ?? "Budget") · \(accountText) · \(transactionText) · exported \(exportedAt.formatted(date: .abbreviated, time: .shortened))"
  }
}

// MARK: - Records

extension BowBackup {
  struct Profile: Codable {
    var id: UUID, currencyCode: String, name: String, createdAt: Date
    var bundledPayeesVersion: Int, dataVersion: Int

    init(_ model: BudgetProfile) {
      id = model.id; currencyCode = model.currencyCode; name = model.name; createdAt = model.createdAt
      bundledPayeesVersion = model.bundledPayeesVersion; dataVersion = model.dataVersion
    }

    var model: BudgetProfile {
      let model = BudgetProfile(currencyCode: currencyCode)
      model.id = id; model.name = name; model.createdAt = createdAt
      model.bundledPayeesVersion = bundledPayeesVersion; model.dataVersion = dataVersion
      return model
    }
  }

  struct Account: Codable {
    var id: UUID, name: String, kindRaw: String, typeRaw: String?, currencyCode: String
    var openingBalanceMinor: Int64, note: String, openedAt: Date, closedAt: Date?
    var lastReconciledAt: Date?, lastReconciledBalanceMinor: Int64?
    var debtGoalStartMinor: Int64?, debtGoalDate: Date?, debtMonthlyTargetMinor: Int64?
    var paymentEnvelopeID: UUID?, institutionName: String?, institutionDomain: String?
    var logoSourceRaw: String?, logoDomain: String?, logoLookupName: String?, customLogoData: Data?

    init(_ model: BudgetAccount) {
      id = model.id; name = model.name; kindRaw = model.kindRaw; typeRaw = model.typeRaw
      currencyCode = model.currencyCode; openingBalanceMinor = model.openingBalanceMinor
      note = model.note; openedAt = model.openedAt; closedAt = model.closedAt
      lastReconciledAt = model.lastReconciledAt; lastReconciledBalanceMinor = model.lastReconciledBalanceMinor
      debtGoalStartMinor = model.debtGoalStartMinor; debtGoalDate = model.debtGoalDate
      debtMonthlyTargetMinor = model.debtMonthlyTargetMinor; paymentEnvelopeID = model.paymentEnvelopeID
      institutionName = model.institutionName; institutionDomain = model.institutionDomain
      logoSourceRaw = model.logoSourceRaw; logoDomain = model.logoDomain
      logoLookupName = model.logoLookupName; customLogoData = model.customLogoData
    }

    var model: BudgetAccount {
      let model = BudgetAccount(name: name, kind: BudgetAccountKind(rawValue: kindRaw) ?? .cash,
                                currencyCode: currencyCode, openingBalanceMinor: openingBalanceMinor)
      model.id = id; model.kindRaw = kindRaw; model.typeRaw = typeRaw; model.note = note
      model.openedAt = openedAt; model.closedAt = closedAt
      model.lastReconciledAt = lastReconciledAt; model.lastReconciledBalanceMinor = lastReconciledBalanceMinor
      model.debtGoalStartMinor = debtGoalStartMinor; model.debtGoalDate = debtGoalDate
      model.debtMonthlyTargetMinor = debtMonthlyTargetMinor; model.paymentEnvelopeID = paymentEnvelopeID
      model.institutionName = institutionName; model.institutionDomain = institutionDomain
      model.logoSourceRaw = logoSourceRaw; model.logoDomain = logoDomain
      model.logoLookupName = logoLookupName; model.customLogoData = customLogoData
      return model
    }
  }

  struct Group: Codable {
    var id: UUID, name: String, sortOrder: Int, isSystem: Bool

    init(_ model: BudgetGroup) {
      id = model.id; name = model.name; sortOrder = model.sortOrder; isSystem = model.isSystem
    }

    var model: BudgetGroup {
      let model = BudgetGroup(name: name, sortOrder: sortOrder)
      model.id = id; model.isSystem = isSystem
      return model
    }
  }

  struct Envelope: Codable {
    var id: UUID, groupID: UUID, name: String, symbol: String, sortOrder: Int
    var targetMinor: Int64?, targetDate: Date?, scheduledTargetMinor: Int64, scheduledTargetMonth: Date?
    var isHidden: Bool, paymentAccountID: UUID?

    init(_ model: BudgetEnvelope) {
      id = model.id; groupID = model.groupID; name = model.name; symbol = model.symbol
      sortOrder = model.sortOrder; targetMinor = model.targetMinor; targetDate = model.targetDate
      scheduledTargetMinor = model.scheduledTargetMinor; scheduledTargetMonth = model.scheduledTargetMonth
      isHidden = model.isHidden; paymentAccountID = model.paymentAccountID
    }

    var model: BudgetEnvelope {
      let model = BudgetEnvelope(groupID: groupID, name: name, symbol: symbol, sortOrder: sortOrder)
      model.id = id; model.targetMinor = targetMinor; model.targetDate = targetDate
      model.scheduledTargetMinor = scheduledTargetMinor; model.scheduledTargetMonth = scheduledTargetMonth
      model.isHidden = isHidden; model.paymentAccountID = paymentAccountID
      return model
    }
  }

  struct Transaction: Codable {
    var id: UUID, accountID: UUID, transferAccountID: UUID?, envelopeID: UUID?
    var date: Date, createdAt: Date, amountMinor: Int64, payee: String, merchantDomain: String?
    var notes: String, kindRaw: String, isCleared: Bool, destinationIsCleared: Bool
    var reconciledAt: Date?, destinationReconciledAt: Date?, sourceRaw: String, externalKey: String?
    var needsApproval: Bool, scheduleID: UUID?, scheduledFor: Date?, isBeforeStart: Bool

    init(_ model: BudgetTransaction) {
      id = model.id; accountID = model.accountID; transferAccountID = model.transferAccountID
      envelopeID = model.envelopeID; date = model.date; createdAt = model.createdAt
      amountMinor = model.amountMinor; payee = model.payee; merchantDomain = model.merchantDomain
      notes = model.notes; kindRaw = model.kindRaw; isCleared = model.isCleared
      destinationIsCleared = model.destinationIsCleared; reconciledAt = model.reconciledAt
      destinationReconciledAt = model.destinationReconciledAt; sourceRaw = model.sourceRaw
      externalKey = model.externalKey; needsApproval = model.needsApproval
      scheduleID = model.scheduleID; scheduledFor = model.scheduledFor; isBeforeStart = model.isBeforeStart
    }

    var model: BudgetTransaction {
      let model = BudgetTransaction(
        accountID: accountID, transferAccountID: transferAccountID, envelopeID: envelopeID,
        date: date, amountMinor: amountMinor, payee: payee, merchantDomain: merchantDomain,
        notes: notes, kind: BudgetTransactionKind(rawValue: kindRaw) ?? .expense
      )
      model.id = id; model.date = date; model.createdAt = createdAt; model.kindRaw = kindRaw
      model.isCleared = isCleared; model.destinationIsCleared = destinationIsCleared
      model.reconciledAt = reconciledAt; model.destinationReconciledAt = destinationReconciledAt
      model.sourceRaw = sourceRaw; model.externalKey = externalKey; model.needsApproval = needsApproval
      model.scheduleID = scheduleID; model.scheduledFor = scheduledFor; model.isBeforeStart = isBeforeStart
      return model
    }
  }

  struct Allocation: Codable {
    var id: UUID, date: Date, createdAt: Date, amountMinor: Int64
    var sourceEnvelopeID: UUID?, sourceCardID: UUID?, targetEnvelopeID: UUID?, targetCardID: UUID?

    init(_ model: BudgetAllocation) {
      id = model.id; date = model.date; createdAt = model.createdAt; amountMinor = model.amountMinor
      sourceEnvelopeID = model.sourceEnvelopeID; sourceCardID = model.sourceCardID
      targetEnvelopeID = model.targetEnvelopeID; targetCardID = model.targetCardID
    }

    var model: BudgetAllocation {
      let model = BudgetAllocation(
        date: date, amountMinor: amountMinor, sourceEnvelopeID: sourceEnvelopeID,
        sourceCardID: sourceCardID, targetEnvelopeID: targetEnvelopeID, targetCardID: targetCardID
      )
      model.id = id; model.createdAt = createdAt
      return model
    }
  }

  struct Payee: Codable {
    var id: UUID, name: String, defaultEnvelopeID: UUID?, exactMatchText: String
    var extraBankNames: [String], merchantDomain: String?, notes: String
    var logoSourceRaw: String, customLogoData: Data?

    init(_ model: BudgetPayee) {
      id = model.id; name = model.name; defaultEnvelopeID = model.defaultEnvelopeID
      exactMatchText = model.exactMatchText; extraBankNames = model.extraBankNames
      merchantDomain = model.merchantDomain; notes = model.notes
      logoSourceRaw = model.logoSourceRaw; customLogoData = model.customLogoData
    }

    var model: BudgetPayee {
      let model = BudgetPayee(name: name, defaultEnvelopeID: defaultEnvelopeID, exactMatchText: exactMatchText)
      model.id = id; model.extraBankNames = extraBankNames; model.merchantDomain = merchantDomain
      model.notes = notes; model.logoSourceRaw = logoSourceRaw; model.customLogoData = customLogoData
      return model
    }
  }

  struct Schedule: Codable {
    var id: UUID, payee: String, amountMinor: Int64, accountID: UUID?, transferAccountID: UUID?
    var envelopeID: UUID?, kindRaw: String, startDate: Date, frequencyRaw: String, notes: String
    var isActive: Bool, reviewedThrough: Date?

    init(_ model: BudgetSchedule) {
      id = model.id; payee = model.payee; amountMinor = model.amountMinor; accountID = model.accountID
      transferAccountID = model.transferAccountID; envelopeID = model.envelopeID; kindRaw = model.kindRaw
      startDate = model.startDate; frequencyRaw = model.frequencyRaw; notes = model.notes
      isActive = model.isActive; reviewedThrough = model.reviewedThrough
    }

    var model: BudgetSchedule {
      let model = BudgetSchedule(
        payee: payee, amountMinor: amountMinor, accountID: accountID, envelopeID: envelopeID,
        startDate: startDate, frequency: ScheduleFrequency(rawValue: frequencyRaw) ?? .monthly, notes: notes,
        kind: BudgetTransactionKind(rawValue: kindRaw) ?? .expense, transferAccountID: transferAccountID
      )
      model.id = id; model.frequencyRaw = frequencyRaw; model.isActive = isActive
      model.reviewedThrough = reviewedThrough
      return model
    }
  }

  struct Occurrence: Codable {
    var id: UUID, scheduleID: UUID, scheduledFor: Date, isSkipped: Bool

    init(_ model: BudgetScheduleOccurrence) {
      id = model.id; scheduleID = model.scheduleID; scheduledFor = model.scheduledFor; isSkipped = model.isSkipped
    }

    var model: BudgetScheduleOccurrence {
      let model = BudgetScheduleOccurrence(scheduleID: scheduleID, scheduledFor: scheduledFor)
      model.id = id; model.isSkipped = isSkipped
      return model
    }
  }

  struct BankLink: Codable {
    var id: UUID, remoteKey: String, name: String, currencyCode: String, localAccountID: UUID?
    var importStartDate: Date?, reportedBalance: String?, reportedAt: Date?
    var institutionName: String?, institutionDomain: String?

    init(_ model: SimpleFINAccountLink) {
      id = model.id; remoteKey = model.remoteKey; name = model.name; currencyCode = model.currencyCode
      localAccountID = model.localAccountID; importStartDate = model.importStartDate
      reportedBalance = model.reportedBalance; reportedAt = model.reportedAt
      institutionName = model.institutionName; institutionDomain = model.institutionDomain
    }

    var model: SimpleFINAccountLink {
      let model = SimpleFINAccountLink(remoteKey: remoteKey, name: name, currencyCode: currencyCode)
      model.id = id; model.localAccountID = localAccountID; model.importStartDate = importStartDate
      model.reportedBalance = reportedBalance; model.reportedAt = reportedAt
      model.institutionName = institutionName; model.institutionDomain = institutionDomain
      return model
    }
  }

  struct BankRecord: Codable {
    var id: UUID, remoteKey: String, localAccountID: UUID, transactionID: UUID?
    var statusRaw: String, originRaw: String, bankStateRaw: String, isVisiblePending: Bool
    var lastSeenAt: Date?, matchedAutomatically: Bool, originalManualSnapshot: Data?
    var date: Date, amountMinor: Int64, payee: String, memo: String, extraJSON: Data?

    init(_ model: SimpleFINImportRecord) {
      id = model.id; remoteKey = model.remoteKey; localAccountID = model.localAccountID
      transactionID = model.transactionID; statusRaw = model.statusRaw; originRaw = model.originRaw
      bankStateRaw = model.bankStateRaw; isVisiblePending = model.isVisiblePending
      lastSeenAt = model.lastSeenAt; matchedAutomatically = model.matchedAutomatically
      originalManualSnapshot = model.originalManualSnapshot; date = model.date
      amountMinor = model.amountMinor; payee = model.payee; memo = model.memo; extraJSON = model.extraJSON
    }

    var model: SimpleFINImportRecord {
      let model = SimpleFINImportRecord(remoteKey: remoteKey, localAccountID: localAccountID,
                                        date: date, amountMinor: amountMinor, payee: payee)
      model.id = id; model.date = date; model.transactionID = transactionID; model.statusRaw = statusRaw
      model.originRaw = originRaw; model.bankStateRaw = bankStateRaw; model.isVisiblePending = isVisiblePending
      model.lastSeenAt = lastSeenAt; model.matchedAutomatically = matchedAutomatically
      model.originalManualSnapshot = originalManualSnapshot; model.memo = memo; model.extraJSON = extraJSON
      return model
    }
  }
}
