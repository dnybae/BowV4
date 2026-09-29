import BackgroundTasks
import Foundation
import SwiftData

enum SimpleFINBackgroundRefresh {
  static var identifier = "app.bitrig.new.b6ec559c-1e09-43ff-a70f-25c814186523.simplefin-refresh"

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
    _ = try? await SimpleFINSyncCoordinator.shared.sync(in: container.mainContext)
    await MerchantEnrichmentCoordinator.shared.run(container: container, maxLookups: 5)
  }
}
