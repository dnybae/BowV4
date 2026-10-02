import Foundation
import SwiftData

/// Changing an account's type, closing it, reopening it and deleting it.
extension BudgetCommands {
  /// Whether anything in the budget refers to the account: transactions on either side,
  /// schedules, or money assigned to its card payment.
  static func accountHasActivity(_ account: BudgetAccount, in context: ModelContext) throws -> Bool {
    let id = account.id
    var transactions = FetchDescriptor<BudgetTransaction>(predicate: #Predicate {
      $0.accountID == id || $0.transferAccountID == id
    })
    transactions.fetchLimit = 1
    if try !context.fetch(transactions).isEmpty { return true }
    if try context.fetch(FetchDescriptor<BudgetSchedule>()).contains(where: {
      $0.accountID == id || $0.transferAccountID == id
    }) { return true }
    return try context.fetch(FetchDescriptor<BudgetAllocation>()).contains {
      $0.sourceCardID == id || $0.targetCardID == id
    }
  }

  /// Changes the type, including between on-budget and off-budget kinds. A kind change is only
  /// allowed before the account has any activity, since it changes what its history means.
  static func changeAccountType(
    _ account: BudgetAccount, to type: BudgetAccountType, in context: ModelContext
  ) throws {
    guard type.kind != account.kind else {
      account.typeRaw = type.rawValue
      return
    }
    guard try !accountHasActivity(account, in: context) else {
      throw BudgetCommandError.accountKindLocked
    }
    if type.kind == .liability && account.openingBalanceMinor > 0 {
      throw BudgetCommandError.liabilityRequiresNegativeBalance
    }
    if account.kind == .credit {
      try removeCardPaymentEnvelope(for: account, in: context)
    }
    account.kindRaw = type.kind.rawValue
    account.typeRaw = type.rawValue
    if type.kind == .credit {
      try ensureCardPaymentEnvelope(for: account, in: context)
    }
  }

  /// Closes an account. It must be at zero, with no card payment money set aside, so closing
  /// never moves money silently. History stays; the account leaves pickers and Budget.
  static func closeAccount(
    _ account: BudgetAccount, balanceMinor: Int64, reservedMinor: Int64, in context: ModelContext
  ) throws {
    guard balanceMinor == 0 else { throw BudgetCommandError.closeNeedsZeroBalance }
    guard reservedMinor == 0 else { throw BudgetCommandError.closeNeedsEmptyCardPayment }
    account.closedAt = Date()
    if let envelopeID = account.paymentEnvelopeID,
       let envelope = try context.fetch(FetchDescriptor<BudgetEnvelope>()).first(where: { $0.id == envelopeID }) {
      envelope.isHidden = true
    }
    for link in try context.fetch(FetchDescriptor<SimpleFINAccountLink>()) where link.localAccountID == account.id {
      link.localAccountID = nil
    }
    try context.save()
  }

  static func reopenAccount(_ account: BudgetAccount, in context: ModelContext) throws {
    account.closedAt = nil
    if let envelopeID = account.paymentEnvelopeID,
       let envelope = try context.fetch(FetchDescriptor<BudgetEnvelope>()).first(where: { $0.id == envelopeID }) {
      envelope.isHidden = false
    }
    try context.save()
  }

  /// Deletes an account nothing refers to yet, with its card payment envelope, any bank items
  /// waiting for it, and its bank link.
  static func deleteUnusedAccount(_ account: BudgetAccount, in context: ModelContext) throws {
    guard try !accountHasActivity(account, in: context) else {
      throw BudgetCommandError.accountHasActivity
    }
    let id = account.id
    try removeCardPaymentEnvelope(for: account, in: context)
    for record in try context.fetch(FetchDescriptor<SimpleFINImportRecord>(
      predicate: #Predicate { $0.localAccountID == id }
    )) {
      context.delete(record)
    }
    for link in try context.fetch(FetchDescriptor<SimpleFINAccountLink>()) where link.localAccountID == id {
      link.localAccountID = nil
    }
    context.delete(account)
    try context.save()
  }

  private static func removeCardPaymentEnvelope(for account: BudgetAccount, in context: ModelContext) throws {
    let id = account.id
    for envelope in try context.fetch(FetchDescriptor<BudgetEnvelope>())
    where envelope.paymentAccountID == id || envelope.id == account.paymentEnvelopeID {
      context.delete(envelope)
    }
    account.paymentEnvelopeID = nil
  }
}
