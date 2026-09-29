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
    in context: ModelContext
  ) throws {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw BudgetCommandError.missingName }
    if account.kind == .liability && currentBalanceMinor > 0 {
      throw BudgetCommandError.liabilityRequiresNegativeBalance
    }
    let now = Date()
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
    account.name = trimmedName
    account.typeRaw = type.rawValue
    account.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if account.kind == .credit {
      try ensureCardPaymentEnvelope(for: account, in: context)
    }
    try context.save()
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

  static func addGroup(name: String, order: Int, in context: ModelContext) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    context.insert(BudgetGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: order))
    try context.save()
  }

  static func addEnvelope(
    name: String,
    symbol: String,
    groupID: UUID,
    order: Int,
    targetMinor: Int64? = nil,
    targetDate: Date? = nil,
    in context: ModelContext
  ) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    guard try context.fetch(FetchDescriptor<BudgetGroup>()).contains(where: {
      $0.id == groupID && !$0.isSystem
    }) else { throw BudgetCommandError.invalidEnvelope }
    let envelope = BudgetEnvelope(
      groupID: groupID,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      symbol: symbol,
      sortOrder: order
    )
    envelope.targetMinor = targetMinor
    envelope.targetDate = targetDate
    context.insert(envelope)
    try context.save()
  }

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
    in context: ModelContext
  ) throws {
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
    try validateTransaction(
      kind: kind,
      account: account,
      destination: destination,
      envelopeID: envelopeID,
      amountMinor: amountMinor
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
    context.insert(transaction)
    try invalidateReconciliation(accountIDs: [account.id, destination?.id].compactMap { $0 }, from: date, in: context)
    try context.save()
  }

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
    in context: ModelContext
  ) throws {
    try validateEnvelopeID(envelopeID, in: context)
    try validateTransaction(kind: kind, account: account, destination: destination,
                            envelopeID: envelopeID, amountMinor: amountMinor)
    let schedule = BudgetSchedule(
      payee: kind == .transfer && payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Transfer to \(destination?.name ?? "Account")"
        : payee.trimmingCharacters(in: .whitespacesAndNewlines), amountMinor: amountMinor,
      accountID: account.id, envelopeID: envelopeID, startDate: startDate,
      frequency: frequency, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind, transferAccountID: kind == .transfer ? destination?.id : nil
    )
    context.insert(schedule)
    try context.save()
    try? ScheduleReviewPlanner().refresh(in: context)
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
    in context: ModelContext
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
    try validateTransaction(
      kind: kind,
      account: account,
      destination: destination,
      envelopeID: envelopeID,
      amountMinor: amountMinor
    )
    let previousAccountIDs = [transaction.accountID, transaction.transferAccountID].compactMap { $0 }
    let earliestDate = min(transaction.date, date)
    transaction.kindRaw = kind.rawValue
    transaction.accountID = account.id
    transaction.transferAccountID = kind == .transfer ? destination?.id : nil
    transaction.envelopeID = envelopeID
    transaction.amountMinor = kind == .inflow ? amountMinor : -amountMinor
    transaction.date = date
    let updatedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
    transaction.merchantDomain = kind == .transfer ? nil : merchantDomain
    transaction.payee = updatedPayee
    transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if let scheduleID, let scheduledFor {
      transaction.scheduleID = scheduleID
      transaction.scheduledFor = scheduledFor
    }
    transaction.needsApproval = false
    transaction.reconciledAt = nil
    transaction.destinationReconciledAt = nil
    try invalidateReconciliation(accountIDs: previousAccountIDs + [account.id, destination?.id].compactMap { $0 }, from: earliestDate, in: context)
    try context.save()
  }

  static func deleteTransaction(_ transaction: BudgetTransaction, in context: ModelContext) throws {
    try invalidateReconciliation(accountIDs: [transaction.accountID, transaction.transferAccountID].compactMap { $0 }, from: transaction.date, in: context)
    context.delete(transaction)
    try context.save()
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
    amountMinor: Int64
  ) throws {
    guard amountMinor > 0 else { throw BudgetCommandError.invalidAmount }
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

  private static func validateEnvelopeID(_ id: UUID?, in context: ModelContext) throws {
    guard let id else { return }
    guard let envelope = try context.fetch(FetchDescriptor<BudgetEnvelope>()).first(where: { $0.id == id }),
          envelope.paymentAccountID == nil else { throw BudgetCommandError.invalidEnvelope }
  }

  static func moveMoney(
    amountMinor: Int64,
    from source: BudgetBucket,
    to target: BudgetBucket,
    date: Date,
    snapshot: BudgetSnapshot,
    in context: ModelContext
  ) throws {
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
  case scheduledTransferMustLinkTransfer
  case currencyMismatch
  case liabilityRequiresNegativeBalance
  case balanceOverflow

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
    case .scheduledTransferMustLinkTransfer: "Record the scheduled transfer, then link the bank entry to that transfer."
    case .currencyMismatch: "This account must use the budget’s currency."
    case .liabilityRequiresNegativeBalance: "Enter money owed on a loan as a negative balance."
    case .balanceOverflow: "That balance change is too large to save safely."
    }
  }
}
