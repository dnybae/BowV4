import Foundation

@main
struct TransactionSheetChecks {
  static func main() {
    // Every purpose has one bottom button title.
    precondition(TransactionSheetPurpose.add.primaryTitle(
      signedAmount: "−$5.00", amountIsZero: false, isScheduling: false) == "Add −$5.00")
    precondition(TransactionSheetPurpose.add.primaryTitle(
      signedAmount: "$0.00", amountIsZero: true, isScheduling: false) == "Add Transaction")
    precondition(TransactionSheetPurpose.add.primaryTitle(
      signedAmount: "−$5.00", amountIsZero: false, isScheduling: true) == "Schedule −$5.00")
    precondition(TransactionSheetPurpose.edit.primaryTitle(
      signedAmount: "", amountIsZero: false, isScheduling: false) == "Save")
    precondition(TransactionSheetPurpose.edit.primaryTitle(
      signedAmount: "−$5.00", amountIsZero: false, isScheduling: true) == "Schedule −$5.00")
    precondition(TransactionSheetPurpose.approve.primaryTitle(
      signedAmount: "", amountIsZero: false, isScheduling: false) == "Approve")
    precondition(TransactionSheetPurpose.enterPending.primaryTitle(
      signedAmount: "", amountIsZero: false, isScheduling: false) == "Enter Now")
    precondition(TransactionSheetPurpose.enterScheduled.primaryTitle(
      signedAmount: "", amountIsZero: false, isScheduling: false) == "Enter Now")

    // Review wins for an existing transaction; Type locks only where the bank or schedule decides.
    precondition(TransactionSheetPurpose(existingNeedsReview: true) == .approve)
    precondition(TransactionSheetPurpose(existingNeedsReview: false) == .edit)
    precondition(!TransactionSheetPurpose.add.locksType && !TransactionSheetPurpose.edit.locksType)
    precondition(TransactionSheetPurpose.approve.locksType && TransactionSheetPurpose.enterPending.locksType)

    // Status line.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    precondition(TransactionSheetStatus(purpose: .add) == nil)
    precondition(TransactionSheetStatus(purpose: .approve, isCleared: true) == .needsReview)
    precondition(TransactionSheetStatus(purpose: .enterPending) == .pendingAtBank)
    precondition(TransactionSheetStatus(purpose: .edit, isPendingAtBank: true, isCleared: true) == .pendingAtBank)
    precondition(TransactionSheetStatus(purpose: .edit, isCleared: true) == .cleared)
    precondition(TransactionSheetStatus(purpose: .edit) == .uncleared)
    precondition(TransactionSheetStatus(
      purpose: .enterScheduled, dueDate: now, now: now, calendar: calendar) == .dueToday)
    precondition(TransactionSheetStatus(
      purpose: .enterScheduled, dueDate: now.addingTimeInterval(-3 * 86_400), now: now,
      calendar: calendar) == .overdue)
    let later = now.addingTimeInterval(3 * 86_400)
    precondition(TransactionSheetStatus(
      purpose: .enterScheduled, dueDate: later, now: now, calendar: calendar) == .due(later))

    // Sure matches only.
    let picker = BankMatchPicker()
    let a = UUID(), b = UUID(), c = UUID(), schedule = UUID()
    // One entered transaction with the exact amount: matched.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, among: [
      .init(id: a, bankAmountMinor: -4_011), .init(id: b, bankAmountMinor: -3_900)
    ]) == a)
    // Two with the same amount: not sure, so nothing.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, among: [
      .init(id: a, bankAmountMinor: -4_011), .init(id: b, bankAmountMinor: -4_011)
    ]) == nil)
    // Same payee but a different amount: not sure.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, among: [
      .init(id: a, bankAmountMinor: -4_500)
    ]) == nil)
    // Nothing nearby.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, among: []) == nil)
    // Already pointing at one, or the recorded scheduled bill, wins over ambiguity.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, linkedID: b, among: [
      .init(id: a, bankAmountMinor: -4_011), .init(id: b, bankAmountMinor: -4_011)
    ]) == b)
    precondition(picker.sureMatch(bankAmountMinor: -4_011, scheduleID: schedule, among: [
      .init(id: a, bankAmountMinor: -4_011), .init(id: c, bankAmountMinor: -4_011, scheduleID: schedule)
    ]) == c)
    // A linked ID that isn't a candidate doesn't count.
    precondition(picker.sureMatch(bankAmountMinor: -4_011, linkedID: c, among: [
      .init(id: a, bankAmountMinor: -4_011)
    ]) == a)

    // Notes: a short single-paragraph memo.
    precondition(NoteText.limited("Lunch with Sam") == "Lunch with Sam")
    precondition(NoteText.limited("Lunch with Sam\n") == "Lunch with Sam")
    precondition(NoteText.limited("Line one\nLine two") == "Line one Line two")
    precondition(NoteText.limited(String(repeating: "a", count: 120)).count == NoteText.maxLength)
    precondition(NoteText.limited("") == "")

        print("TransactionSheetChecks passed")
  }
}
