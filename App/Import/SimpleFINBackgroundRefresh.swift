import BackgroundTasks
import Foundation
import SwiftData

enum SimpleFINBackgroundRefresh {
  /// Matches BGTaskSchedulerPermittedIdentifiers, which is built from the bundle identifier too.
  static let identifier = (Bundle.main.bundleIdentifier ?? "app.bow") + ".simplefin-refresh"

  static func cancel() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }

  @MainActor
  static func schedule(in context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: "bow.demoMode") else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
      return
    }
    guard (try? SimpleFINCredentialStore().load()) != nil else { return }
    guard (try? context.fetch(FetchDescriptor<SimpleFINConnection>()))?
      .first?.automaticSync == true else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
      return
    }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  @MainActor
  static func run(container: ModelContainer) async {
    guard !UserDefaults.standard.bool(forKey: "bow.demoMode") else { return }
    defer { schedule(in: container.mainContext) }
    // Bills due today enter themselves, even before the app is opened.
    try? ScheduleReviewPlanner().refresh(in: container.mainContext)
    _ = try? await SimpleFINSyncCoordinator.shared.sync(in: container.mainContext)
  }
}
