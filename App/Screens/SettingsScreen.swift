import SwiftUI
import SwiftData

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @AppStorage("bow.demoResetVersion") private var demoResetVersion = 0
  @AppStorage("bow.demoScenario") private var demoScenarioRaw = DemoScenario.showcase.rawValue
  @AppStorage("bow.logoDevPublishableKey") private var logoDevPublishableKey = ""
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var simpleFINRecords: [SimpleFINImportRecord]
  @State private var showingYNABImport = false
  @State private var showingBankImport = false
  @State private var showingResetDemo = false

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Budget Settings") {
          NavigationLink {
            CategoryManagementScreen()
          } label: {
            Label("Manage Groups & Envelopes", systemImage: "square.grid.2x2")
          }
          NavigationLink {
            ManagePayeesScreen()
          } label: {
            Label("Manage Payees", systemImage: "person.crop.circle")
          }
          NavigationLink {
            PayeeRulesScreen()
          } label: {
            Label("Payee Rules", systemImage: "person.text.rectangle")
          }
        }

        Section("Bank Connections & Import") {
          NavigationLink {
            SimpleFINScreen()
          } label: {
            HStack {
              Label("SimpleFIN Bank Sync", systemImage: "arrow.clockwise")
              Spacer()
              let count = simpleFINRecords.filter { $0.status == .review }.count
              if count > 0 {
                Text("\(count) to review")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Button("Import Bank File", systemImage: "doc.text") {
            showingBankImport = true
          }
          Button("Import YNAB Categories", systemImage: "square.and.arrow.down") {
            showingYNABImport = true
          }
        }

        Section("Preferences") {
          Picker("Appearance", selection: $appearanceRaw) {
            ForEach(AppAppearance.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          }
          .pickerStyle(.menu)
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Notifications",
              description: "Notification controls will appear here when reminders are available.",
              systemImage: "bell"
            )
          } label: {
            Label("Notifications", systemImage: "bell")
          }
        }

        Section {
          TextField("Logo.dev publishable key (pk_…)", text: $logoDevPublishableKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Merchant Logos")
        } footer: {
          Text("A publishable key enables merchant logos in transaction lists. Merchant names are sent to Logo.dev for matching.")
        }

        Section("Privacy & Legal") {
          LabeledContent("Storage", value: isDemoMode ? "Temporary demo" : "On this iPhone")
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Privacy Policy",
              description: "The privacy policy has not been published in the app yet.",
              systemImage: "hand.raised"
            )
          } label: {
            Label("Privacy Policy", systemImage: "hand.raised")
          }
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Terms of Use",
              description: "The terms of use have not been published in the app yet.",
              systemImage: "doc.text"
            )
          } label: {
            Label("Terms of Use", systemImage: "doc.text")
          }
        }

        Section("About") {
          LabeledContent("Version", value: version)
        }

        Section {
          HStack(spacing: 12) {
            Toggle("Demo Mode", systemImage: "play.rectangle", isOn: $isDemoMode)
            if isDemoMode {
              Menu {
                Picker("Situation", selection: $demoScenarioRaw) {
                  ForEach(DemoScenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario.rawValue)
                  }
                }
                Button("Reset Demo Data", systemImage: "arrow.counterclockwise", role: .destructive) {
                  showingResetDemo = true
                }
              } label: {
                Image(systemName: "ellipsis")
                  .frame(minWidth: 32, minHeight: 44)
                  .contentShape(Rectangle())
              }
              .accessibilityLabel("Demo Options")
            }
          }
        } footer: {
          Text("Sample data stays separate from your budget.")
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
      .sheet(isPresented: $showingBankImport) {
        BankFileImportScreen()
      }
      .confirmationDialog("Reset all demo changes?", isPresented: $showingResetDemo) {
        Button("Reset Demo Data", role: .destructive) {
          dismiss()
          demoResetVersion += 1
        }
      } message: {
        Text("This restores the original sample budget, transactions, schedules, and bank review items.")
      }
    }
  }
}
