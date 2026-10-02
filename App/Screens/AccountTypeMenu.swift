import SwiftUI

/// The account types for a type `Picker`, split into on-budget and off-budget.
struct AccountTypeMenu: View {
  var types: [BudgetAccountType] = BudgetAccountType.allCases

  var body: some View {
    let onBudget = BudgetAccountType.onBudget.filter(types.contains)
    let offBudget = BudgetAccountType.offBudget.filter(types.contains)
    if !onBudget.isEmpty {
      Section("On budget") {
        ForEach(onBudget) { type in
          Label(type.title, systemImage: type.systemImage).tag(type)
        }
      }
    }
    if !offBudget.isEmpty {
      Section("Off budget") {
        ForEach(offBudget) { type in
          Label(type.title, systemImage: type.systemImage).tag(type)
        }
      }
    }
  }
}
