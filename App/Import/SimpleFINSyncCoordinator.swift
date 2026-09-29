import Foundation
import Observation
import SwiftData
import BackgroundTasks

@MainActor @Observable
final class SimpleFINSyncCoordinator {
  static let shared = SimpleFINSyncCoordinator()
  private(set) var isSyncing = false

  private init() {}

  func connect(token: String, startDate: Date? = nil, in context: ModelContext) async throws {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    let accessURL = try await SimpleFINClient().claim(setupToken: token)
    // A setup token can only be claimed once. Save its replacement before any other request.
    try SimpleFINCredentialStore().save(accessURL)
    let connection = try connection(in: context)
    connection.importStartDate = startDate
    try recordRequest(on: connection, at: Date())
    try context.save()
    do {
      let response = try await SimpleFINClient().fetch(
        accessURL: accessURL,
        startDate: max(Date().addingTimeInterval(-89 * 86_400), startDate ?? .distantPast)
      )
      updateAccounts(response.accounts, in: context)
      connection.lastMessage = response.messages.isEmpty ? nil : response.messages.joined(separator: "\n")
      try context.save()
    } catch {
      connection.lastMessage = error.localizedDescription
      try? context.save()
      throw error
    }
  }

  func sync(in context: ModelContext, manual: Bool = false) async throws -> SimpleFINSyncSummary {
    guard !isSyncing else { return SimpleFINSyncSummary() }
    guard let accessURL = try SimpleFINCredentialStore().load() else {
      throw SimpleFINError.noConnection
    }
    let work = ModelContext(context.container)
    let connection = try connection(in: work)
    let now = Date()
    if !manual && !connection.automaticSync { return SimpleFINSyncSummary() }
    let hasMapping = try work.fetch(FetchDescriptor<SimpleFINAccountLink>())
      .contains(where: { $0.localAccountID != nil })
    if !manual && !hasMapping { return SimpleFINSyncSummary() }
    if let last = connection.lastAttemptAt,
       now.timeIntervalSince(last) < (manual ? 10 * 60 : 6 * 60 * 60),
       let successful = connection.lastSuccessfulAt,
       (connection.lastMappingChangeAt ?? .distantPast) <= successful {
      if manual { throw SimpleFINError.refreshTooSoon }
      return SimpleFINSyncSummary()
    }
    isSyncing = true
    defer { isSyncing = false }
    do {
      try recordRequest(on: connection, at: now)
    } catch {
      connection.lastMessage = error.localizedDescription
      try? work.save()
      throw error
    }
    try work.save()

    let earliest = now.addingTimeInterval(-89 * 86_400)
    let mappingChanged = (connection.lastMappingChangeAt ?? .distantPast)
      > (connection.lastSuccessfulAt ?? .distantPast)
    let historyStart = mappingChanged ? earliest
      : max(earliest, (connection.lastSuccessfulAt ?? earliest).addingTimeInterval(-5 * 86_400))
    let start = max(historyStart, connection.importStartDate ?? .distantPast)
    do {
      let response = try await SimpleFINClient().fetch(accessURL: accessURL, startDate: start)
      updateAccounts(response.accounts, in: work)
      try work.save()
      let summary = try await SimpleFINImportRepository(modelContainer: work.container)
        .importTransactions(response.accounts)
      var messages = response.messages
      if let last = connection.lastSuccessfulAt, last < earliest {
        messages.append("This connection was inactive for over 90 days. Check your bank for older transactions that SimpleFIN could not return in this refresh.")
      }
      connection.lastMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
      if response.messages.isEmpty { connection.lastSuccessfulAt = now }
      try work.save()
      return summary
    } catch {
      work.rollback()
      let errorConnection = try? self.connection(in: work)
      errorConnection?.lastMessage = error.localizedDescription
      try? work.save()
      throw error
    }
  }

  func disconnect(in context: ModelContext) throws {
    try SimpleFINCredentialStore().delete()
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: SimpleFINBackgroundRefresh.identifier)
    for link in try context.fetch(FetchDescriptor<SimpleFINAccountLink>()) {
      context.delete(link)
    }
    for connection in try context.fetch(FetchDescriptor<SimpleFINConnection>()) {
      context.delete(connection)
    }
    try context.save()
  }

  func resolve(
    _ record: SimpleFINImportRecord,
    as decision: SimpleFINReviewDecision,
    scheduleID: UUID? = nil,
    scheduledFor: Date? = nil,
    in context: ModelContext
  ) throws {
    guard record.status == .review else { return }
    if let scheduleID, let scheduledFor {
      let linkedSchedule = try context.fetch(FetchDescriptor<BudgetSchedule>()).first { $0.id == scheduleID }
      if linkedSchedule?.kind == .transfer {
        switch decision {
        case .importNew: throw BudgetCommandError.scheduledTransferMustLinkTransfer
        case .link(let id):
          guard try BudgetTransactionLookup.byID(id, in: context)?.kind == .transfer
          else { throw BudgetCommandError.scheduledTransferMustLinkTransfer }
        case .ignore: break
        }
      }
      switch decision {
      case .ignore:
        break
      case .importNew, .link:
        let recorded = try BudgetTransactionLookup.scheduled(
          scheduleID: scheduleID, on: scheduledFor, in: context
        )
        if let recorded {
          if case .link(let id) = decision, id == recorded.id {
            // Linking a bank leg to the already recorded transfer is valid.
          } else {
            throw BudgetCommandError.duplicateScheduledOccurrence
          }
        }
      }
    }
    switch decision {
    case .ignore:
      record.status = .ignored
    case .importNew:
      guard let account = try context.fetch(FetchDescriptor<BudgetAccount>())
        .first(where: { $0.id == record.localAccountID }) else {
        throw SimpleFINError.invalidResponse
      }
      let transaction = Self.makeTransaction(
        account: account, date: record.date,
        amount: record.amountMinor, payee: record.payee, in: context
      )
      transaction.externalKey = record.remoteKey
      transaction.scheduleID = scheduleID
      transaction.scheduledFor = scheduledFor
      try Self.adjustOpeningBalance(for: transaction, account: account)
      context.insert(transaction)
      record.transactionID = transaction.id
      record.status = .imported
    case .link(let id):
      guard let transaction = try BudgetTransactionLookup.byID(id, in: context),
        Self.isPossibleMatch(transaction, for: record) else {
        throw SimpleFINError.invalidResponse
      }
      if let scheduleID, let existingScheduleID = transaction.scheduleID,
         existingScheduleID != scheduleID {
        throw SimpleFINError.invalidResponse
      }
      let otherRecords = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(
        predicate: #Predicate { $0.transactionID == id }
      ))
      guard !otherRecords.contains(where: {
        $0.id != record.id && $0.transactionID == id && $0.status != .ignored
          && (transaction.kind != .transfer || $0.localAccountID == record.localAccountID)
      }) else { throw SimpleFINError.alreadyLinked }
      if transaction.kind != .transfer {
        transaction.amountMinor = record.amountMinor
        transaction.kindRaw = record.amountMinor < 0
          ? BudgetTransactionKind.expense.rawValue : BudgetTransactionKind.inflow.rawValue
      }
      if transaction.transferAccountID == record.localAccountID {
        transaction.destinationIsCleared = true
      } else {
        transaction.isCleared = true
      }
      transaction.needsApproval = true
      if transaction.scheduleID == nil {
        transaction.scheduleID = scheduleID
        transaction.scheduledFor = scheduledFor
      }
      if transaction.sourceRaw == "manual" { transaction.sourceRaw = "manualLinked" }
      if transaction.externalKey == nil { transaction.externalKey = record.remoteKey }
      record.transactionID = transaction.id
      record.status = .linked
      if let account = try context.fetch(FetchDescriptor<BudgetAccount>())
        .first(where: { $0.id == record.localAccountID }),
         let reconciled = account.lastReconciledAt,
         transaction.date <= reconciled {
        account.lastReconciledAt = nil
        account.lastReconciledBalanceMinor = nil
      }
    }
    try context.save()
  }

  func possibleMatches(
    for record: SimpleFINImportRecord,
    among transactions: [BudgetTransaction],
    records: [SimpleFINImportRecord]
  ) -> [BudgetTransaction] {
    let usedIDs = Set(records.filter {
      $0.id != record.id && $0.status != .ignored && $0.localAccountID == record.localAccountID
    }.compactMap(\.transactionID))
    return transactions.filter { !usedIDs.contains($0.id) && Self.isPossibleMatch($0, for: record) }
      .sorted { abs($0.date.timeIntervalSince(record.date)) < abs($1.date.timeIntervalSince(record.date)) }
  }

  nonisolated static func isPossibleMatch(_ transaction: BudgetTransaction, for record: SimpleFINImportRecord) -> Bool {
    let amount = transaction.transferAccountID == record.localAccountID
      ? -transaction.amountMinor : transaction.amountMinor
    let inAccount = transaction.accountID == record.localAccountID
      || transaction.transferAccountID == record.localAccountID
    return inAccount
      && abs(transaction.date.timeIntervalSince(record.date)) <= 10 * 86_400
      && (amount == record.amountMinor
          || (transaction.kind != .transfer && !Self.normalized(record.payee).isEmpty
            && Self.normalized(transaction.payee) == Self.normalized(record.payee)))
      && transaction.externalKey != record.remoteKey
  }

  private func connection(in context: ModelContext) throws -> SimpleFINConnection {
    if let existing = try context.fetch(FetchDescriptor<SimpleFINConnection>()).first {
      return existing
    }
    let created = SimpleFINConnection()
    context.insert(created)
    return created
  }

  private func recordRequest(on connection: SimpleFINConnection, at now: Date) throws {
    if let start = connection.quotaWindowStartedAt,
       now.timeIntervalSince(start) >= 24 * 60 * 60 {
      connection.quotaWindowStartedAt = now
      connection.requestsInWindow = 0
    } else if connection.quotaWindowStartedAt == nil {
      connection.quotaWindowStartedAt = now
    }
    guard connection.requestsInWindow < 24 else { throw SimpleFINError.dailyLimit }
    connection.requestsInWindow += 1
    connection.lastAttemptAt = now
  }

  private func updateAccounts(_ accounts: [SimpleFINRemoteAccount], in context: ModelContext) {
    let existing = (try? context.fetch(FetchDescriptor<SimpleFINAccountLink>())) ?? []
    let byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.remoteKey, $0) })
    for account in accounts {
      if let link = byKey[account.remoteKey] {
        link.name = account.name
        link.currencyCode = account.currency
        link.reportedBalance = account.balance
        link.reportedAt = account.balanceDate.map { Date(timeIntervalSince1970: $0) }
      } else {
        let link = SimpleFINAccountLink(
          remoteKey: account.remoteKey,
          name: account.name,
          currencyCode: account.currency
        )
        link.reportedBalance = account.balance
        link.reportedAt = account.balanceDate.map { Date(timeIntervalSince1970: $0) }
        context.insert(link)
      }
    }
  }

  func importTransactions(
    _ accounts: [SimpleFINRemoteAccount], in context: ModelContext
  ) throws -> SimpleFINSyncSummary {
    try Self.importTransactionsOffMain(accounts, in: context)
  }

  nonisolated static func importTransactionsOffMain(
    _ accounts: [SimpleFINRemoteAccount], in context: ModelContext
  ) throws -> SimpleFINSyncSummary {
    let links = try context.fetch(FetchDescriptor<SimpleFINAccountLink>())
    let localAccounts = try context.fetch(FetchDescriptor<BudgetAccount>())
    let postedDates = accounts.flatMap { account in
      (account.transactions ?? []).filter { $0.pending != true && $0.posted > 0 }.map(\.date)
    }
    guard let earliest = postedDates.min(), let latest = postedDates.max() else {
      return SimpleFINSyncSummary()
    }
    let start = earliest.addingTimeInterval(-11 * 86_400)
    let end = latest.addingTimeInterval(11 * 86_400)
    var transactions = try context.fetch(FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.date >= start && $0.date <= end
    }))
    let records = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate {
      $0.date >= start && $0.date <= end
    }))
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    var knownKeys = Set(records.map(\.remoteKey))
    knownKeys.formUnion(transactions.compactMap(\.externalKey))
    var candidates = transactions.map { transaction in
      LocalTransactionCandidate(
        id: transaction.id, accountID: transaction.accountID,
        amountMinor: transaction.amountMinor, date: transaction.date,
        payee: transaction.payee, externalKey: transaction.externalKey,
        isManual: transaction.sourceRaw == "manual" && transaction.kind != .transfer
      )
    }
    var summary = SimpleFINSyncSummary()
    let matcher = SimpleFINMatchPlanner()

    for remote in accounts where links.contains(where: { $0.remoteKey == remote.remoteKey && $0.localAccountID != nil }) {
      for item in (remote.transactions ?? []) where item.pending != true && item.posted > 0 {
        guard item.amountMinor != nil else { throw SimpleFINError.invalidAmount }
      }
    }

    for remote in accounts {
      guard let link = links.first(where: { $0.remoteKey == remote.remoteKey }),
            let localID = link.localAccountID,
            let account = localAccounts.first(where: { $0.id == localID }),
            remote.currency == account.currencyCode else { continue }
      for item in (remote.transactions ?? []) where item.pending != true && item.posted > 0 {
        guard let amount = item.amountMinor else { throw SimpleFINError.invalidAmount }
        let key = Self.transactionKey(account: remote.remoteKey, transaction: item.id)
        guard knownKeys.insert(key).inserted else { continue }
        let existingRecord = FetchDescriptor<SimpleFINImportRecord>(
          predicate: #Predicate { $0.remoteKey == key }
        )
        let existingTransaction = FetchDescriptor<BudgetTransaction>(
          predicate: #Predicate { $0.externalKey == key }
        )
        guard try context.fetchCount(existingRecord) == 0,
              try context.fetchCount(existingTransaction) == 0 else { continue }
        let payee = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = SimpleFINImportRecord(
          remoteKey: key, localAccountID: localID,
          date: item.date, amountMinor: amount, payee: payee
        )
        let incoming = BankTransactionCandidate(
          externalKey: key, accountID: localID, amountMinor: amount,
          postedAt: item.date,
          transactedAt: item.transactedAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
          description: payee
        )
        let decision = matcher.decide(for: incoming, among: candidates)
        let otherPossible = transactions.contains {
          Self.isPossibleMatch($0, for: record)
            && ($0.kind == .transfer || $0.sourceRaw != "manual")
        }
        let scheduledTransferPossible = schedules.contains { schedule in
          guard schedule.isActive && schedule.kind == .transfer,
                ScheduleRecurrence().occurs(starting: schedule.startDate,
                                            frequency: schedule.frequency, on: item.date) else { return false }
          return (schedule.accountID == localID && amount == -schedule.amountMinor)
            || (schedule.transferAccountID == localID && amount == schedule.amountMinor)
        }
        switch decision {
        case .linkManual(let id) where !otherPossible && !scheduledTransferPossible:
          if let transaction = transactions.first(where: { $0.id == id }) {
            transaction.isCleared = true
            transaction.needsApproval = true
            transaction.sourceRaw = "manualLinked"
            transaction.externalKey = key
            if let candidateIndex = candidates.firstIndex(where: { $0.id == id }) {
              candidates[candidateIndex].externalKey = key
              candidates[candidateIndex].isManual = false
            }
            record.transactionID = id
            record.status = .linked
            summary.linked += 1
          }
        case .createNew where !otherPossible && !scheduledTransferPossible:
          let transaction = Self.makeTransaction(
            account: account, date: item.date,
            amount: amount, payee: payee, in: context
          )
          transaction.externalKey = key
          try Self.adjustOpeningBalance(for: transaction, account: account)
          context.insert(transaction)
          transactions.append(transaction)
          candidates.append(LocalTransactionCandidate(
            id: transaction.id, accountID: transaction.accountID,
            amountMinor: transaction.amountMinor, date: transaction.date,
            payee: transaction.payee, externalKey: key, isManual: false
          ))
          record.transactionID = transaction.id
          record.status = .imported
          summary.imported += 1
        default:
          record.status = .review
          summary.needsReview += 1
        }
        context.insert(record)
      }
    }
    return summary
  }

  nonisolated private static func makeTransaction(
    account: BudgetAccount, date: Date, amount: Int64,
    payee: String, in context: ModelContext
  ) -> BudgetTransaction {
    let kind: BudgetTransactionKind = amount < 0 ? .expense : .inflow
    let transaction = BudgetTransaction(
      accountID: account.id, date: date, amountMinor: amount,
      payee: payee, notes: "", kind: kind
    )
    transaction.sourceRaw = "simplefin"
    transaction.isCleared = true
    transaction.needsApproval = true
    return transaction
  }

  nonisolated private static func adjustOpeningBalance(for transaction: BudgetTransaction, account: BudgetAccount) throws {
    if transaction.date < account.openedAt {
      let (adjusted, overflow) = account.openingBalanceMinor.subtractingReportingOverflow(transaction.amountMinor)
      guard !overflow else { throw SimpleFINError.balanceOverflow }
      account.openingBalanceMinor = adjusted
    }
    if let reconciled = account.lastReconciledAt, transaction.date <= reconciled {
      account.lastReconciledAt = nil
      account.lastReconciledBalanceMinor = nil
    }
  }

  nonisolated private static func transactionKey(account: String, transaction: String) -> String {
    "simplefin|\(Data(account.utf8).base64EncodedString())|\(Data(transaction.utf8).base64EncodedString())"
  }

  nonisolated private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: .punctuationCharacters)
      .joined(separator: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}

struct SimpleFINSyncSummary: Sendable {
  var imported = 0
  var linked = 0
  var needsReview = 0
}

enum SimpleFINReviewDecision {
  case link(UUID)
  case importNew
  case ignore
}
