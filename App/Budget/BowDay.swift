import Foundation

/// Transactions happen on a calendar day, not at an instant. Bow stores each one as noon on
/// its day, so daylight saving, a few hours of time zone travel, or a bank's midnight-UTC
/// timestamp can't move it into the day (or month) next to it.
enum BowDay {
  /// Noon on the calendar day `date` falls on.
  static func normalized(_ date: Date, calendar: Calendar = .current) -> Date {
    let start = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .hour, value: 12, to: start) ?? date
  }

  /// The day a bank timestamp names. Banks that only know the date send midnight or noon UTC;
  /// reading those in local time would put the transaction on the day before in the Americas.
  /// Any other time is a real moment, so it's read on the local calendar.
  static func fromBankTimestamp(_ seconds: TimeInterval, calendar: Calendar = .current) -> Date {
    let instant = Date(timeIntervalSince1970: seconds)
    let secondsIntoUTCDay = Int(seconds.rounded()) % 86_400
    guard secondsIntoUTCDay == 0 || secondsIntoUTCDay == 43_200 else {
      return normalized(instant, calendar: calendar)
    }
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = utc.dateComponents([.year, .month, .day], from: instant)
    let local = calendar.date(from: DateComponents(
      year: parts.year, month: parts.month, day: parts.day, hour: 12
    ))
    return local ?? normalized(instant, calendar: calendar)
  }

  /// The first moment of the day an account's starting balance is as of.
  static func start(of date: Date, calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: date)
  }
}
