import Foundation

/// Picks the transaction you entered that a bank item surely is. Like YNAB, a match is the one
/// entered transaction with exactly the bank amount; Bow never suggests a match it isn't sure of.
struct BankMatchPicker {
  struct Candidate: Equatable {
    var id: UUID
    /// The amount as the bank would see it, e.g. a transfer seen from its receiving account.
    var bankAmountMinor: Int64
    var scheduleID: UUID?
  }

  /// - Parameters:
  ///   - linkedID: A transaction the bank item already points at.
  ///   - scheduleID: A scheduled bill the bank item lines up with; its recorded transaction wins.
  func sureMatch(
    bankAmountMinor: Int64, linkedID: UUID? = nil, scheduleID: UUID? = nil,
    among candidates: [Candidate]
  ) -> UUID? {
    if let linkedID, candidates.contains(where: { $0.id == linkedID }) { return linkedID }
    if let scheduleID, let recorded = candidates.first(where: { $0.scheduleID == scheduleID }) {
      return recorded.id
    }
    let exact = candidates.filter { $0.bankAmountMinor == bankAmountMinor }
    return exact.count == 1 ? exact.first?.id : nil
  }
}
