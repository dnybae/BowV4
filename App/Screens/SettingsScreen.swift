import SwiftUI
import SwiftData

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("bow.appearance") private var appearanceRaw = AppAppearance.system.rawValue
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var simpleFINRecords: [SimpleFINImportRecord]
  @State private var showingYNABImport = false
  @State private var showingBankImport = false

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Appearance", selection: $appearanceRaw) {
            ForEach(AppAppearance.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          }
          .pickerStyle(.menu)
        } header: {
          Text("Appearance")
        } footer: {
          Text("System follows your iPhone’s appearance setting.")
        }

        Section("Categories") {
          NavigationLink {
            CategoryManagementScreen()
          } label: {
            Label("Groups & Envelopes", systemImage: "square.grid.2x2")
          }
          NavigationLink {
            PayeeRulesScreen()
          } label: {
            Label("Payee Rules", systemImage: "person.text.rectangle")
          }
        }

        Section {
          Button("Import Bank File", systemImage: "doc.text") {
            showingBankImport = true
          }
          NavigationLink {
            SimpleFINScreen()
          } label: {
            HStack {
              Label("SimpleFIN Bank Sync", systemImage: "arrow.clockwise")
              Spacer()
              let reviewCount = simpleFINRecords.filter { $0.status == .review }.count
              if reviewCount > 0 {
                Text("\(reviewCount) to review")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
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
          Text("Your budget is stored on this device. SimpleFIN bank sync is optional and uses a credential stored in this device’s Keychain. iCloud sync is not active yet.")
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
      .sheet(isPresented: $showingBankImport) {
        BankFileImportScreen()
      }
    }
  }
}
