import SwiftUI
import SwiftData

struct WelcomeScreen: View {
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @State private var currencyCode = "USD"
  @State private var withDefaults = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Spacer()
            Image(systemName: "figure.archery")
              .font(.system(size: 54, weight: .thin))
              .foregroundStyle(.tint)
              .accessibilityHidden(true)
            Spacer()
          }
          .listRowBackground(Color.clear)
          VStack(alignment: .leading, spacing: 8) {
            Text("Give every dollar a job.")
              .font(.title2.weight(.semibold))
            Text("A calmer way to plan with the money you have.")
              .foregroundStyle(Bow.inkSoft)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .listRowBackground(Color.clear)
        }

        Section {
          Picker("Currency", selection: $currencyCode) {
            Text("US Dollar (USD)").tag("USD")
            Text("Canadian Dollar (CAD)").tag("CAD")
          }
          Toggle("Add starter envelopes", isOn: $withDefaults)
        } header: {
          Text("Your budget")
        } footer: {
          Text("You can also import your YNAB groups and envelopes after creating the budget.")
        }
        .listRowBackground(Bow.card)

        Section {
          Button("Create Budget", systemImage: "arrow.right") {
            do {
              try BudgetCommands.createBudget(
                currencyCode: currencyCode,
                withDefaults: withDefaults,
                in: modelContext
              )
            } catch {
              errorMessage = error.localizedDescription
            }
          }
          .frame(maxWidth: .infinity)
          .fontWeight(.semibold)
        }
        .listRowBackground(Bow.card)

        Section {
          Button("Try Demo Budget", systemImage: "play.rectangle") {
            isDemoMode = true
          }
        } footer: {
          Text("Explore sample accounts, transactions, scheduled bills, and bank review. Your own budget stays separate.")
        }
        .listRowBackground(Bow.card)
      }
      .bowListBackground()
      .navigationTitle("Welcome to Bow")
      .alert("Couldn’t Create Budget", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }
}
