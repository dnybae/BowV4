import Foundation

struct SpendingTimeline {
  var days: [SpendingTimelineDay]

  var isEmpty: Bool { days.isEmpty }

  init(
    transactions: [TransactionListItem],
    reviewTransactions: [BudgetTransaction],
    inbox: ReviewInbox,
    records: [SimpleFINImportRecord],
    accounts: [BudgetAccount],
    envelopes: [BudgetEnvelope],
    currencyCode: String,
    searchText: String,
    filter: TransactionFilter,
    calendar: Calendar = .current,
    now: Date = Date()
  ) {
    let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    let envelopeByID = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, $0) })
    let reviewTransactionByID = Dictionary(
      reviewTransactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )
    let pending = records.filter { $0.bankState == .pending && $0.isVisiblePending }
    let pendingByTransactionID = Dictionary(
      pending.compactMap { record in record.transactionID.map { ($0, record) } },
      uniquingKeysWith: { first, _ in first }
    )
    let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    func includes(
      accountID: UUID, transferAccountID: UUID? = nil, envelopeID: UUID? = nil,
      date: Date, amountMinor: Int64, isUncategorizedExpense: Bool = false,
      needsAttention: Bool, isMatched: Bool = false, searchableText: [String]
    ) -> Bool {
      let candidate = TransactionFilterItem(
        accountID: accountID, transferAccountID: transferAccountID,
        envelopeID: envelopeID, date: date, amountMinor: amountMinor,
        isUncategorizedExpense: isUncategorizedExpense,
        needsAttention: needsAttention, isMatched: isMatched
      )
      return filter.includes(candidate, calendar: calendar)
        && (search.isEmpty || searchableText.contains {
          $0.localizedCaseInsensitiveContains(search)
        })
    }

    var items: [SpendingTimelineItem] = []
    var visibleBankReviews: [SpendingTimelineItem] = []
    for entry in inbox.bankItems {
      guard case .bankRecord(let record, let relatedOccurrence) = entry else { continue }
      let linked = record.transactionID.flatMap { reviewTransactionByID[$0] }
      let account = accountByID[record.localAccountID]
      let envelope = linked?.envelopeID.flatMap { envelopeByID[$0] }
      guard includes(
        accountID: record.localAccountID, transferAccountID: linked?.transferAccountID,
        envelopeID: linked?.envelopeID, date: record.date,
        amountMinor: record.amountMinor,
        isUncategorizedExpense: record.amountMinor < 0 && linked?.envelopeID == nil,
        needsAttention: true,
        searchableText: [record.payee, record.memo, account?.name ?? "", envelope?.name ?? ""]
      ) else { continue }
      visibleBankReviews.append(SpendingTimelineItem(
        id: record.transactionID.map { "transaction-\($0)" } ?? "bank-\(record.id)",
        date: record.date,
        title: record.payee.isEmpty ? "Bank transaction" : record.payee,
        accountName: account?.name ?? "Account",
        envelopeName: envelope?.name,
        amountMinor: record.amountMinor,
        currencyCode: account?.currencyCode ?? currencyCode,
        merchantDomain: linked?.merchantDomain,
        kind: linked?.kind ?? (record.amountMinor < 0 ? .expense : .inflow),
        status: .bankReview,
        source: .bankReview(record, relatedOccurrence)
      ))
    }
    let reviewedTransactionIDs = Set(visibleBankReviews.compactMap { item -> UUID? in
      if case .bankReview(let record, _) = item.source { return record.transactionID }
      return nil
    })

    for transaction in transactions where !reviewedTransactionIDs.contains(transaction.id) {
      let pendingRecord = pendingByTransactionID[transaction.id]
      let needsReview = transaction.needsApproval
        || (transaction.kind == .expense && transaction.envelopeID == nil)
      let status: SpendingTimelineStatus?
      if transaction.kind == .expense && transaction.envelopeID == nil {
        status = .chooseEnvelope
      } else if needsReview {
        status = .transactionReview
      } else if pendingRecord != nil {
        status = .pendingEntered
      } else {
        status = nil
      }
      items.append(SpendingTimelineItem(
        id: "transaction-\(transaction.id)", date: transaction.date,
        title: transaction.kind == .transfer ? "Transfer" :
          transaction.payee.isEmpty ? "Transaction" : transaction.payee,
        accountName: transaction.accountName,
        envelopeName: transaction.envelopeName,
        amountMinor: transaction.amountMinor,
        currencyCode: currencyCode,
        merchantDomain: transaction.merchantDomain,
        kind: transaction.kind,
        status: status,
        source: pendingRecord != nil && !needsReview
          ? .pending(pendingRecord!) : .transaction(transaction.id)
      ))
    }

    items.append(contentsOf: visibleBankReviews)
    var visibleIDs = Set(items.map(\.id))
    for entry in inbox.bankItems {
      guard case .transaction(let transaction) = entry else { continue }
      let id = "transaction-\(transaction.id)"
      guard !visibleIDs.contains(id) else { continue }
      let account = accountByID[transaction.accountID]
      let envelope = transaction.envelopeID.flatMap { envelopeByID[$0] }
      guard includes(
        accountID: transaction.accountID,
        transferAccountID: transaction.transferAccountID,
        envelopeID: transaction.envelopeID,
        date: transaction.date, amountMinor: transaction.amountMinor,
        isUncategorizedExpense: transaction.kind == .expense && transaction.envelopeID == nil,
        needsAttention: true,
        isMatched: transaction.sourceRaw == "manualLinked",
        searchableText: [transaction.payee, transaction.notes,
                         account?.name ?? "", envelope?.name ?? ""]
      ) else { continue }
      items.append(SpendingTimelineItem(
        id: id, date: transaction.date,
        title: transaction.kind == .transfer ? "Transfer" :
          transaction.payee.isEmpty ? "Transaction" : transaction.payee,
        accountName: account?.name ?? "Account", envelopeName: envelope?.name,
        amountMinor: transaction.amountMinor, currencyCode: currencyCode,
        merchantDomain: transaction.merchantDomain, kind: transaction.kind,
        status: transaction.kind == .expense && transaction.envelopeID == nil
          ? .chooseEnvelope : .transactionReview,
        source: .transaction(transaction.id)
      ))
      visibleIDs.insert(id)
    }

    for entry in inbox.scheduledItems {
      guard case .scheduled(let occurrence, let schedule) = entry else { continue }
      let account = schedule.accountID.flatMap { accountByID[$0] }
      let envelope = schedule.envelopeID.flatMap { envelopeByID[$0] }
      guard let accountID = schedule.accountID,
        includes(
          accountID: accountID, transferAccountID: schedule.transferAccountID,
          envelopeID: schedule.envelopeID, date: occurrence.scheduledFor,
          amountMinor: -schedule.amountMinor,
          isUncategorizedExpense: schedule.kind == .expense && schedule.envelopeID == nil,
          needsAttention: true,
          searchableText: [schedule.payee, schedule.notes,
                           account?.name ?? "", envelope?.name ?? ""]
        ) else { continue }
      items.append(SpendingTimelineItem(
        id: "scheduled-\(occurrence.id)", date: occurrence.scheduledFor,
        title: schedule.payee.isEmpty ? "Scheduled bill" : schedule.payee,
        accountName: account?.name ?? "Account", envelopeName: envelope?.name,
        amountMinor: -schedule.amountMinor, currencyCode: currencyCode,
        merchantDomain: nil, kind: schedule.kind, status: .scheduled,
        source: .scheduled(occurrence, schedule)
      ))
    }

    for record in pending {
      let id = record.transactionID.map { "transaction-\($0)" } ?? "pending-\(record.id)"
      guard !visibleIDs.contains(id) else { continue }
      let account = accountByID[record.localAccountID]
      guard includes(
        accountID: record.localAccountID, date: record.date,
        amountMinor: record.amountMinor, needsAttention: false,
        searchableText: [record.payee, record.memo, account?.name ?? ""]
      ) else { continue }
      items.append(SpendingTimelineItem(
        id: id, date: record.date,
        title: record.payee.isEmpty ? "Bank item" : record.payee,
        accountName: account?.name ?? "Account", envelopeName: nil,
        amountMinor: record.amountMinor,
        currencyCode: account?.currencyCode ?? currencyCode,
        merchantDomain: nil,
        kind: record.amountMinor < 0 ? .expense : .inflow,
        status: record.transactionID == nil ? .pending : .pendingEntered,
        source: .pending(record)
      ))
      visibleIDs.insert(id)
    }

    days = SpendingTimelineDay.make(items, calendar: calendar, now: now)
  }
}

struct SpendingTimelineItem: Identifiable {
  enum Source {
    case transaction(UUID)
    case bankReview(SimpleFINImportRecord, BudgetScheduleOccurrence?)
    case pending(SimpleFINImportRecord)
    case scheduled(BudgetScheduleOccurrence, BudgetSchedule)
  }

  var id: String
  var date: Date
  var title: String
  var accountName: String
  var envelopeName: String?
  var amountMinor: Int64
  var currencyCode: String
  var merchantDomain: String?
  var kind: BudgetTransactionKind
  var status: SpendingTimelineStatus?
  var source: Source
}

enum SpendingTimelineStatus {
  case bankReview
  case transactionReview
  case chooseEnvelope
  case pending
  case pendingEntered
  case scheduled

  var title: String {
    switch self {
    case .bankReview: "Review · Match or categorize"
    case .transactionReview: "Review · Needs approval"
    case .chooseEnvelope: "Review · Choose an envelope"
    case .pending: "Pending at bank · Not in budget"
    case .pendingEntered: "Pending at bank · Entered in budget"
    case .scheduled: "Scheduled · Record or skip"
    }
  }

  var needsAttention: Bool {
    switch self {
    case .pending, .pendingEntered: false
    default: true
    }
  }
}

struct SpendingTimelineDay: Identifiable {
  var day: Date
  var title: String
  var items: [SpendingTimelineItem]

  var id: Date { day }

  static func make(
    _ items: [SpendingTimelineItem],
    calendar: Calendar = .current, now: Date = Date()
  ) -> [SpendingTimelineDay] {
    let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
    return byDay.keys.sorted(by: >).map { day in
      let title: String
      if calendar.isDate(day, inSameDayAs: now) {
        title = "Today"
      } else if calendar.isDate(day, inSameDayAs:
        calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
        title = "Yesterday"
      } else {
        title = day.formatted(date: .complete, time: .omitted)
      }
      let sorted = (byDay[day] ?? []).sorted { left, right in
        let leftNeedsAttention = left.status?.needsAttention == true
        let rightNeedsAttention = right.status?.needsAttention == true
        if leftNeedsAttention != rightNeedsAttention { return leftNeedsAttention }
        if left.date != right.date { return left.date > right.date }
        return left.id < right.id
      }
      return SpendingTimelineDay(day: day, title: title, items: sorted)
    }
  }
}
