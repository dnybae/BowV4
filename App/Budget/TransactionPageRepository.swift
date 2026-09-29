import Foundation
import SwiftData

/// The only transaction objects retained by a page fetch live in this actor's context.
/// Views receive small values and use the main context to load a selected transaction.
@ModelActor
actor TransactionPageRepository {
  static let pageSize = 80

  struct Cursor: Sendable {
    var date: Date
    var createdAt: Date
    var equalTimestampOffset: Int
  }

  struct Request: Sendable {
    var accountID: UUID?
    var envelopeID: UUID?
    var payeeKey: String?
    var startDate: Date?
    var endDate: Date?
    var needsApprovalOnly = false
    var uncategorizedOnly = false
    var includesBalanceAdjustments = false
    var minimumAmountMinor: Int64?
    var maximumAmountMinor: Int64?
    var searchText = ""
    var cursor: Cursor?
  }

  struct Page: Sendable {
    var items: [TransactionListItem]
    var nextCursor: Cursor?
  }

  func page(_ request: Request) throws -> Page {
    let startDate = request.startDate ?? .distantPast
    let endDate = request.endDate ?? .distantFuture
    var cursor = request.cursor
    let accounts = try modelContext.fetch(FetchDescriptor<BudgetAccount>())
    let envelopes = try modelContext.fetch(FetchDescriptor<BudgetEnvelope>())
    let accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
    let envelopeNames = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, $0.name) })
    let payees = request.payeeKey == nil ? [] : try modelContext.fetch(FetchDescriptor<BudgetPayee>())
    var aliases: [String: String] = [:]
    for payee in payees {
      let canonical = PayeeDirectory.key(payee.name)
      aliases[canonical] = canonical
      let exact = PayeeDirectory.key(payee.exactMatchText)
      if !exact.isEmpty { aliases[exact] = canonical }
    }
    let search = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    var items: [TransactionListItem] = []
    var more = true
    while items.count < Self.pageSize && more {
      try Task.checkCancellation()
      let activeDate = cursor?.date ?? .distantFuture
      let activeCreatedAt = cursor?.createdAt ?? .distantFuture
      let scopedPredicate: Predicate<BudgetTransaction>
      if let accountID = request.accountID, let envelopeID = request.envelopeID {
        scopedPredicate = #Predicate { item in
          item.date >= startDate && item.date < endDate
            && (item.date < activeDate || (item.date == activeDate && item.createdAt <= activeCreatedAt))
            && (item.accountID == accountID || item.transferAccountID == accountID)
            && item.envelopeID == envelopeID
        }
      } else if let accountID = request.accountID {
        scopedPredicate = #Predicate { item in
          item.date >= startDate && item.date < endDate
            && (item.date < activeDate || (item.date == activeDate && item.createdAt <= activeCreatedAt))
            && (item.accountID == accountID || item.transferAccountID == accountID)
        }
      } else if let envelopeID = request.envelopeID {
        scopedPredicate = #Predicate { item in
          item.date >= startDate && item.date < endDate && item.envelopeID == envelopeID
            && (item.date < activeDate || (item.date == activeDate && item.createdAt <= activeCreatedAt))
        }
      } else {
        scopedPredicate = #Predicate { item in
          item.date >= startDate && item.date < endDate
            && (item.date < activeDate || (item.date == activeDate && item.createdAt <= activeCreatedAt))
        }
      }
      var descriptor = FetchDescriptor<BudgetTransaction>(
        predicate: scopedPredicate,
        sortBy: [SortDescriptor(\.date, order: .reverse),
                 SortDescriptor(\.createdAt, order: .reverse),
                 SortDescriptor(\.id, order: .reverse)]
      )
      descriptor.fetchLimit = 256
      descriptor.fetchOffset = cursor?.equalTimestampOffset ?? 0
      let fetched = try ModelContext(modelContainer).fetch(descriptor)
      let fetchedCount = fetched.count
      var consumed = 0
      for item in fetched {
        consumed += 1
        if cursor?.date == item.date && cursor?.createdAt == item.createdAt {
          cursor?.equalTimestampOffset += 1
        } else {
          cursor = Cursor(date: item.date, createdAt: item.createdAt, equalTimestampOffset: 1)
        }
        if !request.includesBalanceAdjustments
            && item.sourceRaw == BudgetTransaction.balanceAdjustmentSource { continue }
        if let payeeKey = request.payeeKey {
          let normalized = PayeeDirectory.key(item.payee)
          if (aliases[normalized] ?? normalized) != payeeKey { continue }
        }
        if request.needsApprovalOnly && !item.needsApproval { continue }
        if request.uncategorizedOnly && !(item.kind == .expense && item.envelopeID == nil) { continue }
        if let minimum = request.minimumAmountMinor,
           item.amountMinor.magnitude < UInt64(max(0, minimum)) { continue }
        if let maximum = request.maximumAmountMinor,
           item.amountMinor.magnitude > UInt64(max(0, maximum)) { continue }
        if !search.isEmpty && !item.payee.localizedCaseInsensitiveContains(search)
            && !item.notes.localizedCaseInsensitiveContains(search)
            && !(accountNames[item.accountID]?.localizedCaseInsensitiveContains(search) ?? false)
            && !(item.envelopeID.flatMap { envelopeNames[$0] }?.localizedCaseInsensitiveContains(search) ?? false) {
          continue
        }
        items.append(TransactionListItem(
        id: item.id, accountID: item.accountID, transferAccountID: item.transferAccountID,
        envelopeID: item.envelopeID, date: item.date, createdAt: item.createdAt,
        amountMinor: item.amountMinor, payee: item.payee,
        merchantDomain: item.merchantDomain, kindRaw: item.kindRaw,
        sourceRaw: item.sourceRaw,
        needsApproval: item.needsApproval,
        accountName: accountNames[item.accountID] ?? "Account",
        envelopeName: item.envelopeID.flatMap { envelopeNames[$0] }
        ))
        if items.count == Self.pageSize { break }
      }
      more = fetchedCount == 256 || consumed < fetchedCount
    }
    return Page(items: items, nextCursor: more ? cursor : nil)
  }

  func countUncategorized() throws -> Int {
    let adjustment = BudgetTransaction.balanceAdjustmentSource
    let predicate = #Predicate<BudgetTransaction> {
      $0.kindRaw == "expense" && $0.envelopeID == nil
        && $0.sourceRaw != adjustment
    }
    return try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
  }

  func countNeedsApproval() throws -> Int {
    let predicate = #Predicate<BudgetTransaction> { $0.needsApproval }
    return try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
  }

  func hasTransaction(inEnvelope id: UUID) throws -> Bool {
    let predicate = #Predicate<BudgetTransaction> { $0.envelopeID == id }
    return try modelContext.fetchCount(FetchDescriptor(predicate: predicate)) > 0
  }
}
