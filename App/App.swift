import SwiftUI
import SwiftData

@main
struct AppDefinition: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(for: [
      BudgetProfile.self,
      BudgetAccount.self,
      BudgetGroup.self,
      BudgetEnvelope.self,
      BudgetTransaction.self,
      BudgetAllocation.self,
      BudgetPayee.self,
      BudgetSchedule.self
    ])
  }
}
