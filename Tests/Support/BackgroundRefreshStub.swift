import Foundation
import SwiftData

/// Checks run on macOS, where BackgroundTasks isn't available.
enum SimpleFINBackgroundRefresh {
  static let identifier = "checks.simplefin-refresh"
  static func cancel() {}
  @MainActor static func schedule(in context: ModelContext) {}
}
