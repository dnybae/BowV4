import SwiftUI
import SwiftData

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL
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
        Section("Budget") {
          Button {
            budgetNameDraft = profiles.first?.name ?? "My Budget"
            showingRename = true
          } label: {
            HStack {
              Label("Name", systemImage: "pencil")
              Spacer(minLength: 8)
              Text(profiles.first?.name ?? "My Budget")
                .foregroundStyle(Bow.inkSoft)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
          }
          .accessibilityLabel("Rename budget, current name \(profiles.first?.name ?? "My Budget")")
          NavigationLink {
            CategoryManagementScreen()
          } label: {
            Label("Groups and envelopes", systemImage: "square.grid.2x2")
          }
          NavigationLink {
            ManagePayeesScreen()
          } label: {
            Label("Payees", systemImage: "person.crop.circle")
          }
        }
        .listRowBackground(Bow.card)

        Section("Bank and import") {
          NavigationLink {
            SimpleFINScreen()
          } label: {
            Label("SimpleFIN bank sync", systemImage: "link")
          }
          Button("Import a bank file", systemImage: "doc.text") {
            showingBankImport = true
          }
          Button("Import from YNAB", systemImage: "arrow.down.to.line") {
            showingYNABImport = true
          }
        }
        .listRowBackground(Bow.card)

        Section("More") {
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Home inventory",
              description: "A place to track personal items and home supplies is coming soon.",
              systemImage: "shippingbox"
            )
          } label: {
            Label("Home inventory", systemImage: "shippingbox")
          }
        }
        .listRowBackground(Bow.card)

        Section("Preferences") {
          Picker(selection: $appearanceRaw) {
            ForEach(AppAppearance.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          } label: {
            HStack(spacing: Bow.Space.s3) {
              BowTileIcon(systemImage: "circle.lefthalf.filled")
              Text("Appearance")
            }
          }
          .pickerStyle(.menu)
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "App icon",
              description: "Choose from alternate Bow app icons.",
              systemImage: "app.badge",
              isComingSoon: true
            )
          } label: {
            ComingSoonRowLabel(title: "App icon", systemImage: "app.badge")
          }
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
        .listRowBackground(Bow.card)

        Section("Privacy & legal") {
          LabeledContent {
            Text(isDemoMode ? "Temporary demo" : "On this iPhone")
          } label: {
            Label("Storage", systemImage: "internaldrive")
          }
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Privacy policy",
              description: "The privacy policy has not been published in the app yet.",
              systemImage: "hand.raised"
            )
          } label: {
            Label("Privacy policy", systemImage: "hand.raised")
          }
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Terms of use",
              description: "The terms of use have not been published in the app yet.",
              systemImage: "doc.text"
            )
          } label: {
            Label("Terms of use", systemImage: "doc.text")
          }
        }
        .listRowBackground(Bow.card)

        Section("Support") {
          Button("Leave a review", systemImage: "star.bubble") {
            openURL(AppStoreLink.writeReview)
          }
          NavigationLink {
            SettingsPlaceholderScreen(
              title: "Feedback",
              description: "Send ideas and report problems directly from Bow.",
              systemImage: "bubble.left.and.text.bubble.right",
              isComingSoon: true
            )
          } label: {
            ComingSoonRowLabel(title: "Feedback", systemImage: "bubble.left.and.text.bubble.right")
          }
        }
        .listRowBackground(Bow.card)

        Section("About") {
          LabeledContent("Version", value: version)
        }
        .listRowBackground(Bow.card)

        Section {
          HStack(spacing: 12) {
            Toggle("Demo mode", systemImage: "play.rectangle", isOn: $isDemoMode)
            if isDemoMode {
              Menu {
                Picker("Situation", selection: $demoScenarioRaw) {
                  ForEach(DemoScenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario.rawValue)
                  }
                }
                Button("Reset demo data", systemImage: "arrow.counterclockwise", role: .destructive) {
                  showingResetDemo = true
                }
              } label: {
                Image(systemName: "ellipsis")
                  .frame(minWidth: 32, minHeight: 44)
                  .contentShape(Rectangle())
              }
              .accessibilityLabel("Demo options")
            }
          }
        } footer: {
          Text("Sample data stays separate from your budget.")
        }
        .listRowBackground(Bow.card)
      }
      .labelStyle(.bowTile)
      .bowListBackground()
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
