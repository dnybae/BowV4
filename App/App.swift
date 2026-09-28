import SwiftUI
import SwiftData

@main
struct AppDefinition: App {
  private var modelContainer: ModelContainer = {
    try! ModelContainer(for:
      BudgetProfile.self,
      BudgetAccount.self,
      BudgetGroup.self,
      BudgetEnvelope.self,
      BudgetTransaction.self,
      BudgetAllocation.self,
      BudgetPayee.self,
      BudgetSchedule.self,
      BudgetScheduleOccurrence.self,
      SimpleFINConnection.self,
      SimpleFINAccountLink.self,
      SimpleFINImportRecord.self
    )
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(modelContainer)
    .backgroundTask(.appRefresh(SimpleFINBackgroundRefresh.identifier)) {
      await SimpleFINBackgroundRefresh.run(container: modelContainer)
    }
  }
}
