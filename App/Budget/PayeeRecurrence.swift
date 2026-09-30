import Foundation

/// A charge that repeats on a steady cadence, detected from a payee's recent expenses.
struct PayeeRecurrence: Sendable {
  var frequency: ScheduleFrequency
  var amountMinor: Int64
  /// The earlier price, when the latest charge went up.
  var previousAmountMinor: Int64?
  var nextDate: Date
  var accountID: UUID
  var envelopeID: UUID?

  /// Detects a weekly, monthly or yearly charge. Needs at least three charges with steady
  /// spacing and similar amounts, and the latest one can't be overdue.
  static func detect(
    in records: [PayeeActivity.Record], today: Date = Date(), calendar: Calendar = .current
  ) -> PayeeRecurrence? {
    let charges = Array(records.filter { $0.kind == .expense && $0.date <= today }
      .sorted { $0.date < $1.date }
      .suffix(6))
    guard charges.count >= 3, let latest = charges.last else { return nil }

    let gaps = zip(charges, charges.dropFirst()).map { earlier, later in
      calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier.date),
                              to: calendar.startOfDay(for: later.date)).day ?? 0
    }
    guard let frequency = cadence(for: gaps) else { return nil }

    let recentAmounts = charges.suffix(3).map { abs($0.amountMinor) }
    guard let smallest = recentAmounts.min(), let largest = recentAmounts.max(),
          smallest > 0, Double(largest) / Double(smallest) <= 1.25 else { return nil }

    let latestAmount = abs(latest.amountMinor)
    let previousAmount = charges.dropLast().last.map { abs($0.amountMinor) }
    let increased = previousAmount.map { Double(latestAmount) >= Double($0) * 1.01 } ?? false

    let start = calendar.startOfDay(for: today)
    var next = latest.date
    repeat {
      guard let advanced = advance(next, by: frequency, calendar: calendar) else { return nil }
      next = advanced
    } while calendar.startOfDay(for: next) < start

    // A charge that's more than half a cycle late has probably stopped.
    guard let lastExpected = advance(latest.date, by: frequency, calendar: calendar),
          let overdueDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastExpected),
                                                   to: start).day,
          overdueDays <= toleranceDays(for: frequency) else { return nil }

    return PayeeRecurrence(
      frequency: frequency,
      amountMinor: latestAmount,
      previousAmountMinor: increased ? previousAmount : nil,
      nextDate: calendar.startOfDay(for: next),
      accountID: latest.accountID,
      envelopeID: latest.envelopeID
    )
  }

  private static func cadence(for gaps: [Int]) -> ScheduleFrequency? {
    let bands: [(ScheduleFrequency, ClosedRange<Int>)] = [
      (.weekly, 5...9), (.monthly, 25...36), (.yearly, 340...390)
    ]
    return bands.first { _, range in gaps.allSatisfy(range.contains) }?.0
  }

  private static func toleranceDays(for frequency: ScheduleFrequency) -> Int {
    switch frequency {
    case .weekly: 4
    case .monthly: 15
    case .yearly, .once: 60
    }
  }

  private static func advance(_ date: Date, by frequency: ScheduleFrequency, calendar: Calendar) -> Date? {
    switch frequency {
    case .weekly: calendar.date(byAdding: .day, value: 7, to: date)
    case .monthly: calendar.date(byAdding: .month, value: 1, to: date)
    case .yearly: calendar.date(byAdding: .year, value: 1, to: date)
    case .once: nil
    }
  }
}
