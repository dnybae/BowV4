import Foundation

struct AccountBalanceCalculator {
  func calculate(
    before cutoff: Date,
    inclusive: Bool = false,
    accounts: [AccountLedgerItem],
    transactions: [TransactionLedgerItem],
    reportingCurrencyCode: String? = nil
  ) -> AccountBalanceReport {
    let included = accounts.filter { inclusive ? $0.openedAt <= cutoff : $0.openedAt < cutoff }
    let byID = Dictionary(uniqueKeysWithValues: included.map { ($0.id, $0) })
    var balances = Dictionary(uniqueKeysWithValues: included.map { ($0.id, $0.openingBalanceMinor) })
    var issues: [AccountBalanceIssue] = []

    for account in included {
      if let reportingCurrencyCode, account.currencyCode != reportingCurrencyCode {
        issues.append(.currencyMismatch(account.id))
      }
    }
    if reportingCurrencyCode == nil && Set(included.map(\.currencyCode)).count > 1 {
      issues.append(.mixedCurrencies)
    }

    let ordered = transactions.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    for transaction in ordered where inclusive ? transaction.date <= cutoff : transaction.date < cutoff {
      guard let source = byID[transaction.accountID] else {
        issues.append(.missingAccount(transaction.id))
        continue
      }
      let (sourceBalance, sourceOverflow) = balances[source.id, default: 0]
        .addingReportingOverflow(transaction.amountMinor)
      if sourceOverflow {
        issues.append(.overflow)
        continue
      }
      if transaction.kind == .transfer {
        guard let destinationID = transaction.transferAccountID,
              let destination = byID[destinationID] else {
          issues.append(.missingAccount(transaction.id))
          balances[source.id] = sourceBalance
          continue
        }
        guard source.currencyCode == destination.currencyCode else {
          issues.append(.mixedCurrencies)
          continue
        }
        let (destinationBalance, destinationOverflow) = balances[destinationID, default: 0]
          .subtractingReportingOverflow(transaction.amountMinor)
        if destinationOverflow {
          issues.append(.overflow)
          continue
        }
        balances[destinationID] = destinationBalance
      }
      balances[source.id] = sourceBalance
    }

    for account in included where account.kind == .liability
      && balances[account.id, default: 0] > 0 {
      issues.append(.positiveLiability(account.id))
    }

    var netWorth: Int64 = 0
    for balance in balances.values {
      let (sum, overflow) = netWorth.addingReportingOverflow(balance)
      if overflow {
        issues.append(.overflow)
        break
      }
      netWorth = sum
    }
    return AccountBalanceReport(
      balances: balances,
      netWorthMinor: issues.isEmpty ? netWorth : nil,
      issues: issues
    )
  }
}

struct AccountBalanceReport: Sendable {
  var balances: [UUID: Int64]
  var netWorthMinor: Int64?
  var issues: [AccountBalanceIssue]
}

enum AccountBalanceIssue: Equatable, Sendable {
  case currencyMismatch(UUID)
  case mixedCurrencies
  case missingAccount(UUID)
  case positiveLiability(UUID)
  case overflow
}
