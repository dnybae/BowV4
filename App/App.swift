import SwiftUI
import SwiftData

@main
struct AppDefinition: App {
  @State private var store = BowModelStore.load()

  var body: some Scene {
    WindowGroup {
      switch store {
      case .success(let container):
        ContentView()
          .modelContainer(container)
      case .failure(let error):
        StoreUnavailableScreen(message: error.localizedDescription) {
          BowModelStore.reset()
          store = BowModelStore.load()
        }
      }
    }
    .backgroundTask(.appRefresh(SimpleFINBackgroundRefresh.identifier)) {
      guard case .success(let container) = await BowModelStore.load() else { return }
      await SimpleFINBackgroundRefresh.run(container: container)
    }
  }
}

/// The one container for Bow's saved budget, shared by the app, its background refresh and
/// its Siri shortcuts so they never open the store twice.
@MainActor
enum BowModelStore {
  private static var loaded: Result<ModelContainer, Error>?

  static func load() -> Result<ModelContainer, Error> {
    if let loaded, case .success = loaded { return loaded }
    let result = Result { try makeContainer() }
    loaded = result
    return result
  }

  /// Forgets a failed attempt so the next `load()` tries again.
  static func reset() {
    loaded = nil
  }

  static func shared() throws -> ModelContainer {
    try load().get()
  }

  private static func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: Schema(versionedSchema: BowSchemaV1.self),
      migrationPlan: BowMigrationPlan.self
    )
  }
}
