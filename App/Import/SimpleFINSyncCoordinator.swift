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
    let recentStart = max(earliest,
      (connection.lastSuccessfulAt ?? earliest).addingTimeInterval(-5 * 86_400))
    let linkStarts = try work.fetch(FetchDescriptor<SimpleFINAccountLink>())
      .filter { $0.localAccountID != nil }.compactMap(\.importStartDate)
    let start = max(
      mappingChanged ? min(recentStart, linkStarts.min() ?? recentStart) : recentStart,
      connection.importStartDate ?? .distantPast
    )
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
    envelopeID: UUID? = nil,
    scheduleID: UUID? = nil,
    scheduledFor: Date? = nil,
    in context: ModelContext
  ) throws {
    guard record.bankState == .posted else { return }
    let existingImported = try record.transactionID.flatMap {
      try BudgetTransactionLookup.byID($0, in: context)
    }
    guard record.status == .review
      || (record.status == .imported && existingImported.map {
        $0.needsApproval || ($0.kind == .expense && $0.envelopeID == nil)
      } == true) else { return }
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
      if let existingImported, record.status == .imported {
        context.delete(existingImported)
      }
      record.transactionID = nil
      record.status = .ignored
    case .importNew:
      guard let account = try context.fetch(FetchDescriptor<BudgetAccount>())
        .first(where: { $0.id == record.localAccountID }) else {
        throw SimpleFINError.invalidResponse
      }
      guard record.amountMinor >= 0 || envelopeID != nil || existingImported?.envelopeID != nil else {
        throw BudgetCommandError.expenseNeedsEnvelope
      }
      let transaction: BudgetTransaction
      if let existingImported, record.status == .imported {
        transaction = existingImported
        transaction.needsApproval = false
      } else {
        transaction = Self.makeTransaction(
          account: account, date: record.date,
          amount: record.amountMinor, payee: record.payee,
          envelopeID: envelopeID, origin: record.origin
        )
        transaction.externalKey = record.remoteKey
        try Self.adjustOpeningBalance(for: transaction, account: account)
        context.insert(transaction)
      }
      if transaction.envelopeID == nil { transaction.envelopeID = envelopeID }
      transaction.scheduleID = scheduleID
      transaction.scheduledFor = scheduledFor
      record.transactionID = transaction.id
      record.status = .imported
    case .link(let id):
      guard let transaction = try BudgetTransactionLookup.byID(id, in: context),
        Self.isPossibleMatch(transaction, for: record) else {
        throw SimpleFINError.invalidResponse
      }
      if transaction.kind == .expense && transaction.envelopeID == nil && envelopeID == nil {
        throw BudgetCommandError.expenseNeedsEnvelope
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
      record.originalManualSnapshot = try JSONEncoder().encode(ManualTransactionSnapshot(transaction))
      if let existingImported, record.status == .imported {
        context.delete(existingImported)
      }
      if transaction.kind != .transfer {
        transaction.amountMinor = record.amountMinor
        transaction.kindRaw = record.amountMinor < 0
          ? BudgetTransactionKind.expense.rawValue : BudgetTransactionKind.inflow.rawValue
      }
      if transaction.envelopeID == nil { transaction.envelopeID = envelopeID }
      if transaction.transferAccountID == record.localAccountID {
        transaction.destinationIsCleared = true
      } else {
        transaction.isCleared = true
      }
      transaction.needsApproval = false
      if transaction.scheduleID == nil {
        transaction.scheduleID = scheduleID
        transaction.scheduledFor = scheduledFor
      }
      if transaction.sourceRaw == "manual" { transaction.sourceRaw = "manualLinked" }
      if transaction.externalKey == nil { transaction.externalKey = record.remoteKey }
      record.transactionID = transaction.id
      record.status = .linked
      record.matchedAutomatically = false
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

  func enterPending(
    _ record: SimpleFINImportRecord, envelopeID: UUID?, in context: ModelContext
  ) throws {
    if record.amountMinor < 0 && envelopeID == nil {
      throw BudgetCommandError.expenseNeedsEnvelope
    }
    guard record.bankState == .pending, record.transactionID == nil,
          let account = try context.fetch(FetchDescriptor<BudgetAccount>())
            .first(where: { $0.id == record.localAccountID }) else { return }
    let transaction = BudgetTransaction(
      accountID: account.id, envelopeID: envelopeID, date: record.date,
      amountMinor: record.amountMinor, payee: record.payee, notes: "",
      kind: record.amountMinor < 0 ? .expense : .inflow
    )
    context.insert(transaction)
    record.transactionID = transaction.id
    try context.save()
  }

  func unmatch(_ record: SimpleFINImportRecord, in context: ModelContext) throws {
    guard record.status == .linked, let id = record.transactionID,
          let transaction = try BudgetTransactionLookup.byID(id, in: context) else { return }
    let otherLinked = try context.fetch(FetchDescriptor<SimpleFINImportRecord>(
      predicate: #Predicate { $0.transactionID == id }
    )).filter { $0.id != record.id && $0.status == .linked }
    let original = record.originalManualSnapshot.flatMap {
      try? JSONDecoder().decode(ManualTransactionSnapshot.self, from: $0)
    }
    if transaction.amountMinor == record.amountMinor, let original {
      transaction.amountMinor = original.amountMinor
      transaction.kindRaw = original.kindRaw
    }
    if transaction.sourceRaw == "manualLinked" {
      transaction.sourceRaw = original?.sourceRaw ?? "manual"
    }
    if transaction.externalKey == record.remoteKey {
      transaction.externalKey = original?.externalKey
    }
    if otherLinked.isEmpty {
      transaction.scheduleID = original?.scheduleID
      transaction.scheduledFor = original?.scheduledFor
    }
    transaction.isCleared = original?.isCleared ?? false
    transaction.destinationIsCleared = original?.destinationIsCleared ?? false
    transaction.needsApproval = false
    if let remaining = otherLinked.first {
      transaction.sourceRaw = "manualLinked"
      transaction.externalKey = remaining.remoteKey
      if otherLinked.contains(where: { $0.localAccountID == transaction.accountID }) {
        transaction.isCleared = true
      }
      if otherLinked.contains(where: { $0.localAccountID == transaction.transferAccountID }) {
        transaction.destinationIsCleared = true
      }
    }
    record.transactionID = nil
    record.status = .review
    record.matchedAutomatically = false
    record.originalManualSnapshot = nil
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
      && (amount < 0) == (record.amountMinor < 0)
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
    let localAccounts = (try? context.fetch(FetchDescriptor<BudgetAccount>())) ?? []
    for account in accounts {
      if let link = byKey[account.remoteKey] {
        if let institution = account.institution {
          link.institutionName = institution.name
          link.institutionDomain = institution.logoDomain
          if let local = localAccounts.first(where: { $0.id == link.localAccountID }) {
            link.applyInstitution(to: local)
          }
        }
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
        link.institutionName = account.institution?.name
        link.institutionDomain = account.institution?.logoDomain
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
    let dates = accounts.flatMap { account in
      (account.transactions ?? []).filter { $0.amountMinor != nil }.map(\.date)
    }
    let start = (dates.min() ?? Date()).addingTimeInterval(-11 * 86_400)
    let end = (dates.max() ?? Date()).addingTimeInterval(11 * 86_400)
    let transactions = try context.fetch(FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.date >= start && $0.date <= end
    }))
    var addedThisPass: [BudgetTransaction] = []
    var records = try context.fetch(FetchDescriptor<SimpleFINImportRecord>())
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let payees = try context.fetch(FetchDescriptor<BudgetPayee>())
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let validEnvelopeIDs = Set(envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil
    }.map(\.id))
    let rules = PayeeDirectory.ruleItems(payees: payees, validEnvelopeIDs: validEnvelopeIDs)
    let categoryMatcher = PayeeRuleMatcher()
    var byKey = Dictionary(uniqueKeysWithValues: records.map { ($0.remoteKey, $0) })
    let transactionKeys = Set(transactions.compactMap(\.externalKey))
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
    let now = Date()
    var checkedLocalIDs = Set<UUID>()

    for remote in accounts {
      guard let link = links.first(where: { $0.remoteKey == remote.remoteKey }),
            let localID = link.localAccountID,
            let account = localAccounts.first(where: { $0.id == localID }),
            remote.currency == account.currencyCode else { continue }
      if remote.transactions != nil { checkedLocalIDs.insert(localID) }
      // Transactions with an unreadable amount are skipped so the rest of the account still syncs.
      let items = (remote.transactions ?? []).filter { item in
          guard item.amountMinor != nil else { return false }
          if item.isPending { return true }
          if link.importStartDate.map({ item.date >= $0 }) ?? true { return true }
          let key = Self.transactionKey(account: remote.remoteKey, transaction: item.id)
          if byKey[key]?.bankState == .pending { return true }
          let payee = Self.normalized(item.description)
          return !payee.isEmpty && records.contains {
            $0.bankState == .pending && $0.localAccountID == localID
              && Self.normalized($0.payee) == payee
              && abs($0.date.timeIntervalSince(item.date)) <= 3 * 86_400
          }
        }
        .sorted { ($0.isPending ? 0 : 1) < ($1.isPending ? 0 : 1) }
      for item in items {
        guard let amount = item.amountMinor else { continue }
        let key = Self.transactionKey(account: remote.remoteKey, transaction: item.id)
        let payee = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.isPending {
          if let existing = byKey[key] {
            if existing.bankState == .pending {
              existing.date = item.date
              existing.amountMinor = amount
              existing.payee = payee
              existing.apply(extraFrom: item)
              existing.lastSeenAt = now
              existing.isVisiblePending = true
            }
            continue
          }
          guard !transactionKeys.contains(key) else { continue }
          let samePending = records.filter {
            $0.bankState == .pending && $0.localAccountID == localID
              && $0.amountMinor == amount
              && Self.normalized($0.payee) == Self.normalized(payee)
              && abs($0.date.timeIntervalSince(item.date)) <= 2 * 86_400
          }
          let record: SimpleFINImportRecord
          if samePending.count == 1, let existing = samePending.first {
            byKey.removeValue(forKey: existing.remoteKey)
            existing.remoteKey = key
            record = existing
          } else {
            record = SimpleFINImportRecord(
              remoteKey: key, localAccountID: localID,
              date: item.date, amountMinor: amount, payee: payee
            )
            records.append(record)
            context.insert(record)
            summary.pending += 1
          }
          record.bankState = .pending
          record.apply(extraFrom: item)
          record.isVisiblePending = true
          record.lastSeenAt = now
          byKey[key] = record
          continue
        }
        if byKey[key]?.bankState == .posted || transactionKeys.contains(key) { continue }
        let samePending = records.filter {
          $0.bankState == .pending && $0.localAccountID == localID
            && !Self.normalized(payee).isEmpty
            && Self.normalized($0.payee) == Self.normalized(payee)
            && abs($0.date.timeIntervalSince(item.date)) <= 3 * 86_400
        }
        let record: SimpleFINImportRecord
        if let exact = byKey[key] {
          record = exact
        } else if samePending.count == 1, let existing = samePending.first {
          byKey.removeValue(forKey: existing.remoteKey)
          existing.remoteKey = key
          record = existing
        } else {
          record = SimpleFINImportRecord(
            remoteKey: key, localAccountID: localID,
            date: item.date, amountMinor: amount, payee: payee
          )
          records.append(record)
          context.insert(record)
        }
        record.bankState = .posted
        record.isVisiblePending = false
        record.lastSeenAt = now
        record.date = item.date
        record.amountMinor = amount
        record.payee = payee
        record.apply(extraFrom: item)
        byKey[key] = record
        let incoming = BankTransactionCandidate(
          externalKey: key, accountID: localID, amountMinor: amount,
          postedAt: item.date,
          transactedAt: item.transactedAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
          description: payee
        )
        let decision = matcher.decide(for: incoming, among: candidates)
        let otherPossible = (transactions + addedThisPass).contains {
          Self.isPossibleMatch($0, for: record)
            && ($0.kind == .transfer || $0.sourceRaw != "manual")
        }
        let otherStagedPossible = records.contains { existing in
          existing.id != record.id && existing.localAccountID == localID
            && existing.bankState == .posted && existing.status == .review
            && existing.amountMinor == amount
            && !Self.normalized(payee).isEmpty
            && Self.normalized(existing.payee) == Self.normalized(payee)
            && abs(existing.date.timeIntervalSince(item.date)) <= 2 * 86_400
        }
        let scheduledTransferPossible = schedules.contains { schedule in
          guard schedule.isActive && schedule.kind == .transfer,
                ScheduleRecurrence().occurs(starting: schedule.startDate,
                                            frequency: schedule.frequency, on: item.date) else { return false }
          return (schedule.accountID == localID && amount == -schedule.amountMinor)
            || (schedule.transferAccountID == localID && amount == schedule.amountMinor)
        }
        let transactionDate = item.transactedAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
          ?? item.date
        let scheduledExpenses = schedules.filter { schedule in
          schedule.isActive && schedule.kind == .expense
            && schedule.accountID == localID && amount == -schedule.amountMinor
            && (Self.normalized(schedule.payee) == Self.normalized(payee)
              || PayeeDirectory.isSamePayee(schedule.payee, payee, payees: payees))
            && ScheduleRecurrence().occurs(
              starting: schedule.startDate, frequency: schedule.frequency,
              on: transactionDate
            )
            && !(transactions + addedThisPass).contains {
              $0.scheduleID == schedule.id && $0.scheduledFor.map {
                Calendar.current.isDate($0, inSameDayAs: transactionDate)
              } == true
            }
        }
        let scheduledExpense = scheduledExpenses.count == 1 ? scheduledExpenses.first : nil
        let scheduledExpenseAmbiguous = scheduledExpenses.count > 1
        let ruleEnvelopeID = categoryMatcher.envelopeID(for: payee, rules: rules)
        let envelopeID = scheduledExpense?.envelopeID ?? ruleEnvelopeID
        switch decision {
        case .linkManual(let id) where !otherPossible && !otherStagedPossible
          && !scheduledTransferPossible && !scheduledExpenseAmbiguous
          && transactions.first(where: { $0.id == id }).map({
            $0.kind != .expense || $0.envelopeID != nil
          }) == true
          && transactions.first(where: { $0.id == id }).map({ transaction in
            scheduledExpense == nil || (
              (transaction.scheduleID == nil || transaction.scheduleID == scheduledExpense?.id)
                && (scheduledExpense?.envelopeID == nil
                  || transaction.envelopeID == scheduledExpense?.envelopeID)
            )
          }) == true:
          if let transaction = transactions.first(where: { $0.id == id }) {
            record.originalManualSnapshot = try JSONEncoder().encode(ManualTransactionSnapshot(transaction))
            transaction.isCleared = true
            transaction.needsApproval = false
            transaction.sourceRaw = "manualLinked"
            transaction.externalKey = key
            if let scheduledExpense, transaction.scheduleID == nil {
              transaction.scheduleID = scheduledExpense.id
              transaction.scheduledFor = transactionDate
            }
            if let candidateIndex = candidates.firstIndex(where: { $0.id == id }) {
              candidates[candidateIndex].externalKey = key
              candidates[candidateIndex].isManual = false
            }
            record.transactionID = id
            record.status = .linked
            record.matchedAutomatically = true
            summary.linked += 1
          }
        case .createNew where !otherPossible && !otherStagedPossible
          && !scheduledTransferPossible && !scheduledExpenseAmbiguous
          && record.transactionID == nil
          && (amount >= 0 || envelopeID != nil):
          let transaction = Self.makeTransaction(
            account: account, date: item.date, amount: amount, payee: payee,
            envelopeID: envelopeID, origin: .simplefin
          )
          transaction.externalKey = key
          if let scheduledExpense, envelopeID != nil {
            transaction.scheduleID = scheduledExpense.id
            transaction.scheduledFor = transactionDate
          }
          try Self.adjustOpeningBalance(for: transaction, account: account)
          context.insert(transaction)
          addedThisPass.append(transaction)
          candidates.append(LocalTransactionCandidate(
            id: transaction.id, accountID: localID, amountMinor: amount,
            date: transaction.date, payee: payee, externalKey: key,
            isManual: false
          ))
          record.transactionID = transaction.id
          record.status = .imported
          summary.imported += 1
        default:
          record.transactionID = nil
          record.status = .review
          summary.needsReview += 1
        }
      }
    }
    for record in records where record.bankState == .pending
      && checkedLocalIDs.contains(record.localAccountID) && record.lastSeenAt != now {
      record.isVisiblePending = false
    }
    return summary
  }

  nonisolated private static func makeTransaction(
    account: BudgetAccount, date: Date, amount: Int64,
    payee: String, envelopeID: UUID?, origin: BankImportOrigin
  ) -> BudgetTransaction {
    let kind: BudgetTransactionKind = amount < 0 ? .expense : .inflow
    let transaction = BudgetTransaction(
      accountID: account.id, envelopeID: envelopeID, date: date, amountMinor: amount,
      payee: payee, notes: "", kind: kind
    )
    transaction.sourceRaw = origin.rawValue
    transaction.isCleared = true
    transaction.needsApproval = false
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

private extension SimpleFINImportRecord {
  nonisolated func apply(extraFrom item: SimpleFINRemoteTransaction) {
    if let json = item.extraJSON { extraJSON = json }
    let memo = item.memo
    if !memo.isEmpty { self.memo = memo }
  }
}

struct SimpleFINSyncSummary: Sendable {
  var imported = 0
  var linked = 0
  var needsReview = 0
  var pending = 0
}

enum SimpleFINReviewDecision {
  case link(UUID)
  case importNew
  case ignore
}
