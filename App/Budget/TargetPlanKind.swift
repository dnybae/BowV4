import Foundation

/// How a payoff goal or envelope target is set: a fixed amount, or an amount by a date.
enum TargetPlanKind: String, CaseIterable, Identifiable {
  case monthly
  case byDate

  var id: String { rawValue }
}
