import Foundation
import SwiftData

/// Stores each envelope's scheduled-bill target for the current month.
/// Run after any schedule changes and when the month rolls over.
struct ScheduleTargetSynchronizer {
  var calendar: Calendar = .current

  func refresh(in context: ModelContext, today: Date = Date()) throws {
    let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
    let schedules = try context.fetch(FetchDescriptor<BudgetSchedule>())
    let envelopes = try context.fetch(FetchDescriptor<BudgetEnvelope>())
    let totals = ScheduleTargetCalculator(calendar: calendar).totalsByEnvelope(schedules: schedules, month: month)
    var changed = false
    for envelope in envelopes {
      let total = totals[envelope.id, default: 0]
      guard envelope.scheduledTargetMinor != total || envelope.scheduledTargetMonth != month else { continue }
      envelope.scheduledTargetMinor = total
      envelope.scheduledTargetMonth = month
      changed = true
    }
    if changed { try context.save() }
  }
}
