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
    in context: ModelContext
  ) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    context.insert(BudgetAccount(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind,
      currencyCode: currencyCode,
      openingBalanceMinor: openingBalanceMinor
    ))
    try context.save()
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
    in context: ModelContext
  ) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw BudgetCommandError.missingName }
    let envelope = BudgetEnvelope(
      groupID: groupID,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      symbol: symbol,
      sortOrder: order
    )
    envelope.targetMinor = targetMinor
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
    notes: String,
    scheduleID: UUID? = nil,
    scheduledFor: Date? = nil,
    in context: ModelContext
  ) throws {
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
      notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind
    )
    transaction.scheduleID = scheduleID
    transaction.scheduledFor = scheduledFor
    context.insert(transaction)
    try context.save()
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
    notes: String,
    in context: ModelContext
  ) throws {
    try validateTransaction(
      kind: kind,
      account: account,
      destination: destination,
      envelopeID: envelopeID,
      amountMinor: amountMinor
    )
    transaction.kindRaw = kind.rawValue
    transaction.accountID = account.id
    transaction.transferAccountID = kind == .transfer ? destination?.id : nil
    transaction.envelopeID = envelopeID
    transaction.amountMinor = kind == .inflow ? amountMinor : -amountMinor
    transaction.date = date
    transaction.payee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
    transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    transaction.needsApproval = false
    try context.save()
  }

  static func deleteTransaction(_ transaction: BudgetTransaction, in context: ModelContext) throws {
    context.delete(transaction)
    try context.save()
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
      if account.kind == .cash && (destination.kind == .asset || destination.kind == .liability)
        && envelopeID == nil {
        throw BudgetCommandError.trackingTransferNeedsEnvelope
      }
    }
  }

  static func moveMoney(
    amountMinor: Int64,
    from source: BudgetBucket,
    to target: BudgetBucket,
    snapshot: BudgetSnapshot,
    date: Date,
    in context: ModelContext
  ) throws {
    guard amountMinor > 0 else { throw BudgetCommandError.invalidAmount }
    guard source != target else {
      throw BudgetCommandError.invalidTransfer
    }
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
}

enum BudgetCommandError: LocalizedError {
  case missingName
  case invalidAmount
  case invalidTransfer
  case unsupportedCardTransfer
  case trackingTransferNeedsEnvelope
  case insufficientFunds

  var errorDescription: String? {
    switch self {
    case .missingName: "Enter a name."
    case .invalidAmount: "Enter an amount greater than zero."
    case .invalidTransfer: "Choose a different destination."
    case .unsupportedCardTransfer: "Use a cash account to pay a credit card."
    case .trackingTransferNeedsEnvelope:
      "Choose an envelope to fund this transfer to a tracking account."
    case .insufficientFunds: "There isn’t enough available money in that source."
    }
  }
}
