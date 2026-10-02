import SwiftUI
import SwiftData

struct WelcomeScreen: View {
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  /// Canadian dollars in Canada; US dollars everywhere else Bow supports today.
  @State private var currencyCode = Locale.current.currency?.identifier == "CAD" ? "CAD" : "USD"
  @State private var withDefaults = true
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: Bow.Space.s5) {
            PulseTarget(size: 220) {
              Image("BowMark")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(Bow.bow)
            }
            .accessibilityHidden(true)
            VStack(spacing: Bow.Space.s2) {
              Text("Give every dollar a job.")
                .font(.bowLargeTitle)
                .foregroundStyle(Bow.ink)
                .accessibilityAddTraits(.isHeader)
              Text("A calmer way to plan with the money you have.")
                .font(.bowBody)
                .foregroundStyle(Bow.inkSoft)
            }
            .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, Bow.Space.s6)
          .listRowBackground(Color.clear)
        }

        Section {
          Picker("Currency", selection: $currencyCode) {
            Text("US Dollar").tag("USD")
            Text("Canadian Dollar").tag("CAD")
          }
          Toggle("Add starter envelopes", isOn: $withDefaults)
        } footer: {
          Text("You can also import your YNAB groups and envelopes after creating the budget.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)

        Section {
          VStack(spacing: Bow.Space.s3) {
            Button {
              do {
                try BudgetCommands.createBudget(
                  currencyCode: currencyCode,
                  withDefaults: withDefaults,
                  in: modelContext
                )
              } catch {
                errorMessage = error.localizedDescription
              }
            } label: {
              Text("Create my budget")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .bowPrimaryButton()

            Button {
              isDemoMode = true
            } label: {
              Text("Try the demo budget")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .bowSecondaryButton()

            Text("The demo uses sample accounts, transactions and bills. Your own budget stays separate.")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
              .multilineTextAlignment(.center)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
      }
      .bowListBackground {
        Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn, height: 700) }
      }
      .toolbar(.hidden, for: .navigationBar)
      .bowErrorAlert("Couldn’t create budget", message: $errorMessage)
    }
  }
}
