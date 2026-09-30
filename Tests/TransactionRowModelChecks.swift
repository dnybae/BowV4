import Foundation

@main
struct TransactionRowModelChecks {
  static func main() {
    func item(
      payee: String = "Trader Joe's", kind: BudgetTransactionKind = .expense,
      envelopeID: UUID? = UUID(), envelopeName: String? = "Groceries",
      needsApproval: Bool = false, amount: Int64 = -5_420
    ) -> TransactionListItem {
      TransactionListItem(
        id: UUID(), accountID: UUID(), transferAccountID: nil, envelopeID: envelopeID,
        date: Date(), createdAt: Date(), amountMinor: amount, payee: payee, merchantDomain: nil,
        kindRaw: kind.rawValue, sourceRaw: "manual", needsApproval: needsApproval,
        accountName: "Checking", envelopeName: envelopeName
      )
    }

    // A normal expense: payee title, envelope then account.
    let normal = TransactionRowModel(item())
    precondition(normal.title == "Trader Joe's" && normal.state == .normal)
    precondition(normal.subtitle(hiding: []) == "Groceries · Checking")
    precondition(normal.subtitle(hiding: .hidesAccount) == "Groceries")
    precondition(normal.subtitle(hiding: .hidesEnvelope) == "Checking")
    precondition(normal.subtitle(hiding: [.hidesAccount, .hidesEnvelope]) == nil)
    precondition(!normal.isInflow)

    // Needs approval wins over a missing envelope.
    let review = TransactionRowModel(item(envelopeID: nil, envelopeName: nil, needsApproval: true))
    guard case .attention(let label, _) = review.state else { preconditionFailure("Expected attention") }
    precondition(label == "Needs review")

    // An expense without an envelope asks for one.
    let unassigned = TransactionRowModel(item(envelopeID: nil, envelopeName: nil))
    guard case .attention(let label2, _) = unassigned.state else { preconditionFailure("Expected attention") }
    precondition(label2 == "Choose an envelope")

    // Income without an envelope is fine, and reads as money coming in.
    let income = TransactionRowModel(item(payee: "Employer", kind: .inflow, envelopeID: nil, envelopeName: nil, amount: 250_000))
    precondition(income.state == .normal && income.isInflow)

    // Transfers get a fixed title and no merchant logo lookup.
    let transfer = TransactionRowModel(item(payee: "", kind: .transfer, envelopeID: nil, envelopeName: nil))
    precondition(transfer.title == "Transfer" && transfer.logoName.isEmpty && transfer.state == .normal)

    // Empty payees still get a readable title.
    precondition(TransactionRowModel(item(payee: "")).title == "Transaction")

    // Amount override (a transfer seen from the receiving account).
    precondition(TransactionRowModel(item(amount: -1_000), amountMinor: 1_000).isInflow)

    // Money coming in carries a plus sign so direction doesn't rely on color.
    precondition(BudgetMoney.formatted(1_000, currencyCode: "USD", showsPlusSign: true).hasPrefix("+"))
    precondition(!BudgetMoney.formatted(0, currencyCode: "USD", showsPlusSign: true).hasPrefix("+"))

    print("Transaction row model checks passed")
  }
}
