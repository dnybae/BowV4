import SwiftUI
import SwiftData

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @Query private var profiles: [BudgetProfile]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var showingYNABImport = false
  var onShowAccounts: () -> Void

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Theme", selection: $appearanceRaw) {
            ForEach(AppAppearance.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Appearance")
        } footer: {
          Text("System follows your iPhone’s appearance setting.")
        }

        Section {
          LabeledContent("Currency", value: currencyCode)
          Button("Accounts", systemImage: "banknote", action: onShowAccounts)
          NavigationLink {
            CategoryManagementScreen(currencyCode: currencyCode)
          } label: {
            Label("Groups & Envelopes", systemImage: "square.grid.2x2")
          }
        } header: {
          Text("Budget")
        } footer: {
          Text("A budget uses one currency. Its currency stays fixed after creation to preserve transaction amounts.")
        }

        Section {
          Button("Import YNAB Categories", systemImage: "square.and.arrow.down") {
            showingYNABImport = true
          }
        } header: {
          Text("Import")
        } footer: {
          Text("Bring over category groups and envelopes from a YNAB Plan export. Recreate targets and balances in Bow.")
        }

        Section {
          LabeledContent("Storage", value: "On this iPhone")
          Label("No Bow account required", systemImage: "lock.shield")
        } header: {
          Text("Data & Privacy")
        } footer: {
          Text("Your budget is stored on this device. iCloud sync and bank connections are not active yet.")
        }

        Section("About") {
          LabeledContent("Version", value: version)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showingYNABImport) {
        YNABImportScreen(groups: groups, envelopes: envelopes)
      }
    }
  }
}
