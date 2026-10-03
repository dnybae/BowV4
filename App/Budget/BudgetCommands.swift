import Foundation
import SwiftData

struct BudgetCommands {
  static func createBudget(currencyCode: String, withDefaults: Bool, in context: ModelContext) throws {
    guard try context.fetchCount(FetchDescriptor<BudgetProfile>()) == 0 else { return }
    context.insert(BudgetProfile(currencyCode: currencyCode))
    if withDefaults {
      let starterGroups: [(String, [(String, String)])] = [
        ("Food & Home", [
          ("Groceries", "cart.fill"),
          ("Housing", "house.fill"),
          ("Utilities", "bolt.fill"),
          ("Dining Out", "fork.knife")
        ]),
        ("Getting Around", [
          ("Transportation", "car.fill"),
          ("Auto Care", "wrench.adjustable.fill")
        ]),
        ("Lifestyle", [
          ("Shopping", "bag.fill"),
          ("Health", "heart.fill"),
          ("Fun", "sparkles")
        ]),
        ("Future", [
          ("Emergency Fund", "cross.case.fill"),
          ("Savings", "banknote.fill")
        ])
      ]
      for (index, item) in starterGroups.enumerated() {
        let group = BudgetGroup(name: item.0, sortOrder: index)
        context.insert(group)
        for (envelopeIndex, envelope) in item.1.enumerated() {
          context.insert(BudgetEnvelope(
            groupID: group.id,
            name: envelope.0,
            symbol: envelope.1,
            sortOrder: envelopeIndex
          ))
        }
      }
    }
    try context.save()
  }

  static func addAccount(
    name: String,
    kind: BudgetAccountKind,
    currencyCode: String,
    openingBalanceMinor: Int64,
    type: BudgetAccountType? = nil,
    note: String = "",
    logoSettings: AccountLogoSettings = AccountLogoSettings(),
    startDate: Date = Date(),
    in context: ModelContext
  ) throws -> BudgetAccount {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    if let profile = try context.fetch(FetchDescriptor<BudgetProfile>()).first,
       profile.currencyCode != currencyCode { throw BudgetCommandError.currencyMismatch }
    if kind == .liability && openingBalanceMinor > 0 {
      throw BudgetCommandError.liabilityRequiresNegativeBalance
    }
    let account = BudgetAccount(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind,
      currencyCode: currencyCode,
      openingBalanceMinor: openingBalanceMinor,
      type: type,
      note: note.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    account.logoSettings = logoSettings
    account.openedAt = BowDay.start(of: startDate)
    context.insert(account)
    if kind == .credit {
      try ensureCardPaymentEnvelope(for: account, in: context)
    }
    try context.save()
    return account
  }

  static func updateAccount(
    _ account: BudgetAccount,
    name: String,
    type: BudgetAccountType,
    note: String,
    currentBalanceMinor: Int64,
    existingBalanceMinor: Int64,
    logoSettings: AccountLogoSettings? = nil,
    startDate: Date? = nil,
    in context: ModelContext
  ) throws {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw BudgetCommandError.missingName }
    if account.kind == .liability && currentBalanceMinor > 0 {
      throw BudgetCommandError.liabilityRequiresNegativeBalance
    }
    let now = Date()
    if let startDate, BowDay.start(of: startDate) != account.openedAt {
      try moveStartingBalanceDate(of: account, to: startDate,
                                  keepingBalance: existingBalanceMinor, in: context)
    }
    let (delta, overflow) = currentBalanceMinor.subtractingReportingOverflow(existingBalanceMinor)
    guard !overflow else { throw BudgetCommandError.balanceOverflow }
    if delta != 0 {
      let adjustment = BudgetTransaction(
        accountID: account.id, date: now, amountMinor: delta,
        payee: "Balance Adjustment", notes: "Current balance updated",
        kind: delta > 0 ? .inflow : .expense
      )
      adjustment.sourceRaw = BudgetTransaction.balanceAdjustmentSource
      context.insert(adjustment)
      account.lastReconciledAt = nil
      account.lastReconciledBalanceMinor = nil
    }
    if let logoSettings { account.logoSettings = logoSettings }
    account.name = trimmedName
    account.typeRaw = type.rawValue
    account.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if account.kind == .credit {
      try ensureCardPaymentEnvelope(for: account, in: context)
    }
    try context.save()
  }

  /// Moves the day an account's starting balance is as of, keeping today's balance unchanged:
  /// the starting balance absorbs whatever moves into or out of history.
  static func moveStartingBalanceDate(
    of account: BudgetAccount, to startDate: Date, keepingBalance balanceMinor: Int64,
    in context: ModelContext
  ) throws {
    account.openedAt = BowDay.start(of: startDate)
    try refreshStartFlags(forAccountIDs: [account.id], in: context)
    let id = account.id
    let counted = try context.fetch(FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      !$0.isBeforeStart && ($0.accountID == id || $0.transferAccountID == id)
    })).reduce(Int64(0)) { total, transaction in
      let leg = transaction.accountID == id ? transaction.amountMinor
        : (transaction.kind == .transfer ? -transaction.amountMinor : 0)
      return total + leg
    }
    let (opening, overflow) = balanceMinor.subtractingReportingOverflow(counted)
    guard !overflow else { throw BudgetCommandError.balanceOverflow }
    account.openingBalanceMinor = opening
    account.lastReconciledAt = nil
    account.lastReconciledBalanceMinor = nil
  }

  static func ensureCardPaymentEnvelopes(in context: ModelContext) throws {
    for card in try context.fetch(FetchDescriptor<BudgetAccount>()) where card.kind == .credit {
      try ensureCardPaymentEnvelope(for: card, in: context)
    }
    try context.save()
  }

  static func ensureCardPaymentEnvelope(for card: BudgetAccount, in context: ModelContext) throws {
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    if let existing = envelopes.first(where: {
      $0.paymentAccountID == card.id || $0.id == card.paymentEnvelopeID
    }) {
      card.paymentEnvelopeID = existing.id
      existing.paymentAccountID = card.id
      existing.name = card.name + " Payment"
      return
    }
    let groups = try context.fetch(FetchDescriptor<BudgetGroup>())
    let group: BudgetGroup
    if let existing = groups.first(where: { $0.isSystem && $0.name == "Credit Card Payments" }) {
      group = existing
    } else {
      group = BudgetGroup(name: "Credit Card Payments", sortOrder: -1)
      group.isSystem = true
      context.insert(group)
    }
    let payment = BudgetEnvelope(groupID: group.id, name: card.name + " Payment", symbol: "creditcard.fill", sortOrder: envelopes.filter { $0.groupID == group.id }.count)
    payment.paymentAccountID = card.id
    card.paymentEnvelopeID = payment.id
    context.insert(payment)
  }

  @discardableResult
  static func addGroup(name: String, order: Int, in context: ModelContext) throws -> BudgetGroup {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    let group = BudgetGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: order)
    context.insert(group)
    try context.save()
    return group
  }

  /// Adds an envelope at the end of its group. An envelope of the same name that was hidden in
  /// that group comes back instead, with its history, rather than being duplicated.
  static func addEnvelope(
    name: String,
    symbol: String,
    groupID: UUID,
    targetMinor: Int64? = nil,
    targetDate: Date? = nil,
    in context: ModelContext
  ) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw BudgetCommandError.missingName }
    guard try context.fetch(FetchDescriptor<BudgetGroup>()).contains(where: {
      $0.id == groupID && !$0.isSystem
    }) else { throw BudgetCommandError.invalidEnvelope }
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    if let hidden = envelopes.first(where: {
      $0.isHidden && $0.groupID == groupID && $0.paymentAccountID == nil
        && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      hidden.isHidden = false
      if let targetMinor { hidden.targetMinor = targetMinor }
      if let targetDate { hidden.targetDate = targetDate }
      try context.save()
      return
    }
    let envelope = BudgetEnvelope(
      groupID: groupID,
      name: trimmed,
      symbol: symbol,
      sortOrder: try nextEnvelopeOrder(in: groupID, context: context)
    )
    envelope.targetMinor = targetMinor
    envelope.targetDate = targetDate
    context.insert(envelope)
    try context.save()
  }

  /// The sort order that puts an envelope last in its group.
  static func nextEnvelopeOrder(in groupID: UUID, context: ModelContext) throws -> Int {
    let orders = try context.fetch(FetchDescriptor<BudgetEnvelope>())
      .filter { $0.groupID == groupID }.map(\.sortOrder)
    return (orders.max() ?? -1) + 1
  }

  @discardableResult
  static func addTransaction(
    kind: BudgetTransactionKind,
    account: BudgetAccount,
    destination: BudgetAccount?,
    envelopeID: UUID?,
    amountMinor: Int64,
    date: Date,
    payee: String,
    merchantDomain: String? = nil,
    notes: String,
    scheduleID: UUID? = nil,
    scheduledFor: Date? = nil,
    in context: ModelContext,
    saving: Bool = true
  ) throws -> BudgetTransaction {
    try validateEnvelopeID(envelopeID, in: context)
    guard Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date()) else {
      throw BudgetCommandError.futureTransactionNeedsSchedule
    }
    if let scheduleID, let scheduledFor {
      let alreadyRecorded = try BudgetTransactionLookup.scheduled(
        scheduleID: scheduleID, on: scheduledFor, in: context
      ) != nil
      guard !alreadyRecorded else { throw BudgetCommandError.duplicateScheduledOccurrence }
    }
    let beforeStart = isBeforeStart(date: date, account: account, destination: kind == .transfer ? destination : nil)
    try validateTransaction(
      kind: kind,
      account: account,
      destination: destination,
      envelopeID: envelopeID,
      amountMinor: amountMinor,
      isBeforeStart: beforeStart
    )
    let signedAmount = kind == .inflow ? amountMinor : -amountMinor
    let transaction = BudgetTransaction(
      accountID: account.id,
      transferAccountID: kind == .transfer ? destination?.id : nil,
      envelopeID: envelopeID,
      date: date,
      amountMinor: signedAmount,
      payee: payee.trimmingCharacters(in: .whitespacesAndNewlines),
      merchantDomain: merchantDomain,
      notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind
    )
    transaction.scheduleID = scheduleID
    transaction.scheduledFor = scheduledFor
    transaction.isBeforeStart = beforeStart
    context.insert(transaction)
    try invalidateReconciliation(accountIDs: [account.id, destination?.id].compactMap { $0 }, from: date, in: context)
    if saving { try context.save() }
    return transaction
  }

  @discardableResult
  static func addSchedule(
    kind: BudgetTransactionKind,
    account: BudgetAccount,
    destination: BudgetAccount?,
    envelopeID: UUID?,
    amountMinor: Int64,
    startDate: Date,
    frequency: ScheduleFrequency,
    payee: String,
    notes: String,
    in context: ModelContext,
    saving: Bool = true
  ) throws -> BudgetSchedule {
    try validateEnvelopeID(envelopeID, in: context)
    try validateTransaction(kind: kind, account: account, destination: destination,
                            envelopeID: envelopeID, amountMinor: amountMinor, isBeforeStart: false)
    let schedule = BudgetSchedule(
      payee: kind == .transfer && payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Transfer to \(destination?.name ?? "Account")"
        : payee.trimmingCharacters(in: .whitespacesAndNewlines), amountMinor: amountMinor,
      accountID: account.id, envelopeID: envelopeID, startDate: startDate,
      frequency: frequency, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind, transferAccountID: kind == .transfer ? destination?.id : nil
    )
    context.insert(schedule)
    if saving {
      try context.save()
      try? ScheduleReviewPlanner().refresh(in: context)
      try? ScheduleTargetSynchronizer().refresh(in: context)
    }
    return schedule
  }

  static func updateTransaction(
    _ transaction: BudgetTransaction,
    kind: BudgetTransactionKind,
    account: BudgetAccount,
    destination: BudgetAccount?,
    envelopeID: UUID?,
    amountMinor: Int64,
    date: Date,
    payee: String,
    merchantDomain: String? = nil,
    notes: String,
    scheduleID: UUID? = nil,
    scheduledFor: Date? = nil,
    in context: ModelContext,
    saving: Bool = true
  ) throws {
    try validateEnvelopeID(envelopeID, in: context)
    guard Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date()) else {
      throw BudgetCommandError.futureTransactionNeedsSchedule
    }
    if let scheduleID, let scheduledFor {
      let alreadyRecorded = try BudgetTransactionLookup.scheduled(
        scheduleID: scheduleID, on: scheduledFor,
        excluding: transaction.id, in: context
      ) != nil
      guard !alreadyRecorded else { throw BudgetCommandError.duplicateScheduledOccurrence }
    }
    let beforeStart = isBeforeStart(date: date, account: account, destination: kind == .transfer ? destination : nil)
    try validateTransaction(
      kind: kind,
      account: account,
      destination: destination,
      envelopeID: envelopeID,
      amountMinor: amountMinor,
      isBeforeStart: beforeStart || transaction.isBalanceAdjustment
    )
    let previousAccountIDs = [transaction.accountID, transaction.transferAccountID].compactMap { $0 }
    let earliestDate = min(transaction.date, date)
    transaction.kindRaw = kind.rawValue
    transaction.accountID = account.id
    transaction.transferAccountID = kind == .transfer ? destination?.id : nil
    transaction.envelopeID = envelopeID
    transaction.amountMinor = kind == .inflow ? amountMinor : -amountMinor
    transaction.date = BowDay.normalized(date)
    let updatedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
    transaction.merchantDomain = kind == .transfer ? nil : merchantDomain
    transaction.payee = updatedPayee
    transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if let scheduleID, let scheduledFor {
      transaction.scheduleID = scheduleID
      transaction.scheduledFor = scheduledFor
    }
    transaction.isBeforeStart = beforeStart
    transaction.needsApproval = false
    transaction.reconciledAt = nil
    transaction.destinationReconciledAt = nil
    try invalidateReconciliation(accountIDs: previousAccountIDs + [account.id, destination?.id].compactMap { $0 }, from: earliestDate, in: context)
    if saving { try context.save() }
  }

  static func deleteTransaction(
    _ transaction: BudgetTransaction, in context: ModelContext, saving: Bool = true
  ) throws {
    try invalidateReconciliation(accountIDs: [transaction.accountID, transaction.transferAccountID].compactMap { $0 }, from: transaction.date, in: context)
    let id = transaction.id
    for record in try context.fetch(FetchDescriptor<SimpleFINImportRecord>(
      predicate: #Predicate { $0.transactionID == id }
    )) {
      record.transactionID = nil
      if record.bankState == .posted {
        record.status = record.status == .linked ? .review : .ignored
      }
      record.originalManualSnapshot = nil
      record.matchedAutomatically = false
    }
    // A bill's date that's deleted is skipped, so it isn't entered again.
    if let scheduleID = transaction.scheduleID, let scheduledFor = transaction.scheduledFor {
      try skipScheduledDate(scheduleID: scheduleID, on: scheduledFor, in: context)
    }
    context.delete(transaction)
    if saving { try context.save() }
  }

  /// Marks one date of a schedule skipped; the schedule stays active for future dates.
  static func skipScheduledDate(scheduleID: UUID, on date: Date, in context: ModelContext) throws {
    let calendar = Calendar.current
    let occurrences = try context.fetch(FetchDescriptor<BudgetScheduleOccurrence>(
      predicate: #Predicate { $0.scheduleID == scheduleID }
    ))
    if let occurrence = occurrences.first(where: { calendar.isDate($0.scheduledFor, inSameDayAs: date) }) {
      occurrence.isSkipped = true
    } else {
      let skipped = BudgetScheduleOccurrence(scheduleID: scheduleID, scheduledFor: calendar.startOfDay(for: date))
      skipped.isSkipped = true
      context.insert(skipped)
    }
  }

  private static func invalidateReconciliation(accountIDs: [UUID], from date: Date, in context: ModelContext) throws {
    let ids = Set(accountIDs)
    for account in try context.fetch(FetchDescriptor<BudgetAccount>()) where ids.contains(account.id) {
      if let reconciled = account.lastReconciledAt,
         Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: reconciled) {
        account.lastReconciledAt = nil
        account.lastReconciledBalanceMinor = nil
      }
    }
  }

  private static func validateTransaction(
    kind: BudgetTransactionKind,
    account: BudgetAccount,
    destination: BudgetAccount?,
    envelopeID: UUID?,
    amountMinor: Int64,
    isBeforeStart: Bool
  ) throws {
    guard amountMinor > 0 else { throw BudgetCommandError.invalidAmount }
    // History from before the starting balance is already counted, so it needs no envelope.
    if kind == .expense && envelopeID == nil && !isBeforeStart {
      throw BudgetCommandError.expenseNeedsEnvelope
    }
    if kind == .transfer {
      guard let destination, destination.id != account.id,
            destination.currencyCode == account.currencyCode else {
        throw BudgetCommandError.invalidTransfer
      }
      if account.kind == .credit {
        throw BudgetCommandError.unsupportedCardTransfer
      }
      if !(account.kind == .cash && (destination.kind == .asset || destination.kind == .liability))
        && envelopeID != nil {
        throw BudgetCommandError.invalidEnvelope
      }
      if account.kind == .cash && (destination.kind == .asset || destination.kind == .liability)
        && envelopeID == nil {
        throw BudgetCommandError.trackingTransferNeedsEnvelope
      }
    }
  }

  /// Whether a transaction on `date` falls before its account's starting balance (or, for a
  /// transfer, either account's). Such a transaction is history: the balance already includes it.
  static func isBeforeStart(date: Date, account: BudgetAccount, destination: BudgetAccount?) -> Bool {
    [account, destination].compactMap { $0 }.contains { date < BowDay.start(of: $0.openedAt) }
  }

  /// Re-marks every transaction in `accountIDs` after a starting balance date changes.
  static func refreshStartFlags(forAccountIDs accountIDs: Set<UUID>, in context: ModelContext) throws {
    let accounts = Dictionary(
      try context.fetch(FetchDescriptor<BudgetAccount>()).map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for transaction in try context.fetch(FetchDescriptor<BudgetTransaction>()) {
      guard accountIDs.contains(transaction.accountID)
        || transaction.transferAccountID.map(accountIDs.contains) == true,
        let account = accounts[transaction.accountID] else { continue }
      let destination = transaction.kind == .transfer ? transaction.transferAccountID.flatMap { accounts[$0] } : nil
      let flag = isBeforeStart(date: transaction.date, account: account, destination: destination)
      if transaction.isBeforeStart != flag { transaction.isBeforeStart = flag }
    }
  }

  private static func validateEnvelopeID(_ id: UUID?, in context: ModelContext) throws {
    guard let id else { return }
    guard let envelope = try context.fetch(FetchDescriptor<BudgetEnvelope>()).first(where: { $0.id == id }),
          envelope.paymentAccountID == nil else { throw BudgetCommandError.invalidEnvelope }
  }

  @discardableResult
  static func moveMoney(
    amountMinor: Int64,
    from source: BudgetBucket,
    to target: BudgetBucket,
    date: Date,
    snapshot: BudgetSnapshot,
    in context: ModelContext
  ) throws -> BudgetAllocation {
    guard amountMinor > 0 else { throw BudgetCommandError.invalidAmount }
    let calendar = Calendar.current
    let targetMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
    let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    guard targetMonth >= currentMonth else { throw BudgetCommandError.pastMonthLocked }
    guard source != target else {
      throw BudgetCommandError.invalidTransfer
    }
    let accounts = try context.fetch(FetchDescriptor<BudgetAccount>())
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let envelopeIDs = Set(envelopes.filter { $0.paymentAccountID == nil }.map(\.id))
    let cardIDs = Set(accounts.filter { $0.kind == .credit }.map(\.id))
    for bucket in [source, target] {
      switch bucket {
      case .readyToAssign: break
      case .envelope(let id): guard envelopeIDs.contains(id) else { throw BudgetCommandError.invalidTransfer }
      case .cardPayment(let id): guard cardIDs.contains(id) else { throw BudgetCommandError.invalidTransfer }
      }
    }
    guard calendar.isDate(snapshot.month, equalTo: date, toGranularity: .month)
    else { throw BudgetCommandError.invalidTransfer }
    let available: Int64
    switch source {
    case .readyToAssign:
      available = snapshot.readyToAssignMinor
    case .envelope(let id):
      available = snapshot.available(for: id)
    case .cardPayment(let id):
      available = snapshot.paymentAvailable[id, default: 0]
    }
    guard amountMinor <= max(0, available) else {
      throw BudgetCommandError.insufficientFunds
    }
    let allocation = BudgetAllocation(date: date, amountMinor: amountMinor)
    switch source {
    case .readyToAssign:
      break
    case .envelope(let id):
      allocation.sourceEnvelopeID = id
    case .cardPayment(let id):
      allocation.sourceCardID = id
    }
    switch target {
    case .readyToAssign:
      break
    case .envelope(let id):
      allocation.targetEnvelopeID = id
    case .cardPayment(let id):
      allocation.targetCardID = id
    }
    context.insert(allocation)
    try context.save()
    return allocation
  }

  /// When a money move for `month` is recorded: now for the current month, otherwise the month's
  /// last moment (past) or first moment (future), so it lands inside the month being budgeted.
  static func allocationDate(inMonth month: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
    let monthInterval = calendar.dateInterval(of: .month, for: month)
    if calendar.isDate(month, equalTo: now, toGranularity: .month) {
      return now
    } else if month < now {
      return monthInterval?.end.addingTimeInterval(-1) ?? month
    } else {
      return monthInterval?.start ?? month
    }
  }

  /// Covers one overspent envelope from one or more donors in a single save: every donor is checked
  /// against the same snapshot, and nothing is recorded unless all of them are valid.
  /// Donors can be Ready to Assign or other budget envelopes; card payment money can't be used,
  /// because taking it would leave that card's debt uncovered.
  static func coverOverspending(
    envelopeID: UUID,
    from donors: [BudgetBucket: Int64],
    date: Date,
    snapshot: BudgetSnapshot,
    in context: ModelContext
  ) throws {
    let calendar = Calendar.current
    let targetMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
    let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    guard targetMonth >= currentMonth else { throw BudgetCommandError.pastMonthLocked }
    guard calendar.isDate(snapshot.month, equalTo: date, toGranularity: .month)
    else { throw BudgetCommandError.invalidTransfer }
    let donors = donors.filter { $0.value != 0 }
    guard !donors.isEmpty, donors.values.allSatisfy({ $0 > 0 }) else { throw BudgetCommandError.invalidAmount }

    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let budgetEnvelopeIDs = Set(envelopes.filter { $0.paymentAccountID == nil }.map(\.id))
    guard budgetEnvelopeIDs.contains(envelopeID) else { throw BudgetCommandError.invalidEnvelope }
    let overspent = max(0, -snapshot.available(for: envelopeID))
    guard overspent > 0 else { throw BudgetCommandError.nothingToCover }

    var total: Int64 = 0
    for (donor, amount) in donors {
      let available: Int64
      switch donor {
      case .readyToAssign:
        available = snapshot.readyToAssignMinor
      case .envelope(let id):
        guard id != envelopeID, budgetEnvelopeIDs.contains(id) else { throw BudgetCommandError.invalidTransfer }
        available = snapshot.available(for: id)
      case .cardPayment:
        throw BudgetCommandError.invalidTransfer
      }
      guard amount <= max(0, available) else { throw BudgetCommandError.insufficientFunds }
      total += amount
    }
    guard total <= overspent else { throw BudgetCommandError.coverExceedsOverspending }

    for (donor, amount) in donors.sorted(by: { $0.value > $1.value }) {
      let allocation = BudgetAllocation(date: date, amountMinor: amount)
      if case .envelope(let id) = donor { allocation.sourceEnvelopeID = id }
      allocation.targetEnvelopeID = envelopeID
      context.insert(allocation)
    }
    try context.save()
  }

  static func setEnvelopeHidden(
    _ envelope: BudgetEnvelope, hidden: Bool,
    availableMinor: Int64, in context: ModelContext
  ) throws {
    if hidden {
      guard availableMinor >= 0 else {
        throw BudgetCommandError.hiddenOverspending
      }
    }
    guard envelope.paymentAccountID == nil else { throw BudgetCommandError.cardPaymentEnvelopeProtected }
    envelope.isHidden = hidden
    try context.save()
  }

  static func deleteEmptyGroup(_ group: BudgetGroup, in context: ModelContext) throws {
    guard !group.isSystem else { throw BudgetCommandError.groupNotEmpty }
    let hasEnvelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>()).contains { $0.groupID == group.id }
    guard !hasEnvelopes else { throw BudgetCommandError.groupNotEmpty }
    context.delete(group)
    try context.save()
  }

  static func deleteUnusedEnvelope(_ envelope: BudgetEnvelope, in context: ModelContext) throws {
    guard envelope.paymentAccountID == nil else { throw BudgetCommandError.cardPaymentEnvelopeProtected }
    let id = envelope.id
    let hasTransactions = try BudgetTransactionLookup.inEnvelope(id, in: context)
    let hasAllocations = try context.fetch(FetchDescriptor<BudgetAllocation>()).contains {
      $0.sourceEnvelopeID == id || $0.targetEnvelopeID == id
    }
    let hasSchedules = try context.fetch(FetchDescriptor<BudgetSchedule>()).contains { $0.envelopeID == id }
    let hasPayeeRules = try context.fetch(FetchDescriptor<BudgetPayee>()).contains { $0.defaultEnvelopeID == id }
    guard !hasTransactions && !hasAllocations && !hasSchedules && !hasPayeeRules else {
      throw BudgetCommandError.envelopeHasHistory
    }
    context.delete(envelope)
    try context.save()
  }
}

enum BudgetCommandError: LocalizedError {
  case missingName
  case invalidAmount
  case invalidTransfer
  case unsupportedCardTransfer
  case trackingTransferNeedsEnvelope
  case insufficientFunds
  case envelopeHasHistory
  case duplicateScheduledOccurrence
  case hiddenOverspending
  case groupNotEmpty
  case pastMonthLocked
  case cardPaymentEnvelopeProtected
  case futureTransactionNeedsSchedule
  case invalidEnvelope
  case expenseNeedsEnvelope
  case scheduledTransferMustLinkTransfer
  case currencyMismatch
  case liabilityRequiresNegativeBalance
  case balanceOverflow
  case nothingToCover
  case coverExceedsOverspending
  case accountKindLocked
  case accountHasActivity
  case closeNeedsZeroBalance
  case closeNeedsEmptyCardPayment

  var errorDescription: String? {
    switch self {
    case .missingName: "Enter a name."
    case .invalidAmount: "Enter an amount greater than zero."
    case .invalidTransfer: "Choose a different destination."
    case .unsupportedCardTransfer: "Use a cash account to pay a credit card."
    case .trackingTransferNeedsEnvelope:
      "Choose an envelope to fund this transfer to a tracking account."
    case .insufficientFunds: "There isn’t enough available money in that source."
    case .envelopeHasHistory: "This envelope has budget history. Hide it to preserve past activity."
    case .duplicateScheduledOccurrence: "This scheduled bill has already been recorded for that day."
    case .hiddenOverspending: "Cover this envelope’s overspending before hiding it."
    case .groupNotEmpty: "Move or remove the envelopes in this group before deleting it."
    case .pastMonthLocked: "Past budget months are view only. Choose this month or a future month."
    case .cardPaymentEnvelopeProtected: "Credit card payment envelopes are managed with their accounts."
    case .futureTransactionNeedsSchedule: "Schedule future transactions and record them when they occur."
    case .invalidEnvelope: "Choose a spending envelope. Card payment envelopes are funded automatically or with Move Money."
    case .expenseNeedsEnvelope: "Choose an envelope for this expense."
    case .scheduledTransferMustLinkTransfer: "Record the scheduled transfer, then link the bank entry to that transfer."
    case .currencyMismatch: "This account must use the budget’s currency."
    case .liabilityRequiresNegativeBalance: "Enter money owed on a loan as a negative balance."
    case .balanceOverflow: "That balance change is too large to save safely."
    case .nothingToCover: "This envelope isn’t overspent anymore."
    case .coverExceedsOverspending: "That’s more than this envelope is overspent. Lower an amount."
    case .accountKindLocked:
      "This account already has transactions, so it can only change to a type of the same kind."
    case .accountHasActivity:
      "This account has transactions or schedules, so it can’t be deleted. Close it instead."
    case .closeNeedsZeroBalance:
      "Bring the balance to zero first, with a transfer or by updating the balance."
    case .closeNeedsEmptyCardPayment:
      "Move the money set aside for this card’s payment back to Ready to Assign first."
    }
  }
}
