import SwiftUI
import SwiftData

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @AppStorage("bow.demoResetVersion") private var demoResetVersion = 0
  @AppStorage("bow.demoScenario") private var demoScenarioRaw = DemoScenario.showcase.rawValue
  @Query private var profiles: [BudgetProfile]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var showingYNABImport = false
  @State private var showingBankImport = false
  @State private var showingResetDemo = false
  @State private var showingRename = false
  @State private var budgetNameDraft = ""

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Budget Settings") {
          Button {
            budgetNameDraft = profiles.first?.name ?? "My Budget"
            showingRename = true
          } label: {
            HStack {
              Label("Budget Name", systemImage: "pencil")
              Spacer(minLength: 8)
              Text(profiles.first?.name ?? "My Budget")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
          }
          .accessibilityLabel("Rename Budget, current name \(profiles.first?.name ?? "My Budget")")
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
            Label("SimpleFIN Bank Sync", systemImage: "arrow.clockwise")
          }
          Button("Import Bank File", systemImage: "doc.text") {
            showingBankImport = true
          }
          Button("Import YNAB Categories", systemImage: "square.and.arrow.down") {
            showingYNABImport = true
          }
        }

        Section("More") {
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Home Inventory",
              description: "A place to track personal items and home supplies is coming soon.",
              systemImage: "shippingbox"
            )
          } label: {
            Label("Home Inventory", systemImage: "shippingbox")
          }
        }

        Section("Preferences") {
          Picker(selection: $appearanceRaw) {
            ForEach(AppAppearance.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          } label: {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
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
      .alert("Rename Budget", isPresented: $showingRename) {
        TextField("Budget Name", text: $budgetNameDraft)
        Button("Cancel", role: .cancel) {}
        Button("Save") {
          let name = budgetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
          if !name.isEmpty {
            profiles.first?.name = name
            try? modelContext.save()
          }
        }
      } message: {
        Text("Choose a name for this budget.")
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
