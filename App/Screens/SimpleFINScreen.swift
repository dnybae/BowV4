import SwiftUI
import SwiftData

struct SimpleFINScreen: View {
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @Query private var connections: [SimpleFINConnection]
  @Query private var links: [SimpleFINAccountLink]
  @Query private var accounts: [BudgetAccount]
  @State private var coordinator = SimpleFINSyncCoordinator.shared
  @State private var message: String?
  @State private var showingDisconnect = false

  private var connection: SimpleFINConnection? { connections.first }
  private var linkedAccounts: [SimpleFINAccountLink] {
    links.filter { $0.localAccountID != nil }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  private var availableCount: Int { links.filter { $0.localAccountID == nil }.count }
  private var connectionStatus: String {
    if isDemoMode { return "Sample connection" }
    if linkedAccounts.isEmpty { return "No accounts syncing" }
    if let connection, let attempted = connection.lastAttemptAt,
       attempted > (connection.lastSuccessfulAt ?? .distantPast),
       connection.lastMessage != nil {
      return "Sync needs attention"
    }
    return "Connected"
  }

  var body: some View {
    Form {
      if let connection {
        Section {
          LabeledContent("Status", value: connectionStatus)
          if let date = connection.lastSuccessfulAt {
            LabeledContent("Last updated", value: date.formatted(date: .abbreviated, time: .shortened))
          }
          if !isDemoMode {
            Toggle("Automatic Sync", isOn: Binding(
              get: { connection.automaticSync },
              set: { enabled in
                let previous = connection.automaticSync
                connection.automaticSync = enabled
                do {
                  try modelContext.save()
                  SimpleFINBackgroundRefresh.schedule(in: modelContext)
                } catch {
                  connection.automaticSync = previous
                  message = error.localizedDescription
                }
              }
            ))
            Button("Sync Now", systemImage: "arrow.clockwise") {
              Task { await sync() }
            }
            .disabled(coordinator.isSyncing)
          }
        } header: {
          Text("Connection")
        } footer: {
          Text(isDemoMode
            ? "Sample bank data never contacts a real bank. Try its transaction examples in Spending."
            : "Bow checks while you use the app and requests background refresh when iOS allows it. Bank data may update about once a day.")
        }

        if let lastMessage = connection.lastMessage, !lastMessage.isEmpty {
          Section("Connection Message") {
            Text(lastMessage).foregroundStyle(.secondary)
          }
        }

        Section {
          if linkedAccounts.isEmpty {
            Text("No bank accounts have been added to Bow yet.")
              .foregroundStyle(.secondary)
          }
          ForEach(linkedAccounts) { link in
            VStack(alignment: .leading, spacing: 4) {
              Text(accounts.first { $0.id == link.localAccountID }?.name ?? "Bow account")
                .font(.body.weight(.medium))
              Text("Bank account: \(link.name)")
                .font(.caption).foregroundStyle(.secondary)
              if let reportedAt = link.reportedAt {
                Text("Bank data as of \(reportedAt.formatted(date: .abbreviated, time: .shortened))")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 3)
          }
          if availableCount > 0 && !isDemoMode {
            NavigationLink {
              SimpleFINAccountSetupScreen()
            } label: {
              Label("Add \(availableCount) Available \(availableCount == 1 ? "Account" : "Accounts")", systemImage: "plus")
            }
          }
        } header: {
          Text("Accounts syncing with Bow")
        } footer: {
          Text("To change or stop an account’s bank sync, open that account from Accounts.")
        }

        if !isDemoMode {
          Section {
            Button("Disconnect SimpleFIN", role: .destructive) {
              showingDisconnect = true
            }
          } footer: {
            Text("This stops sync for every linked account. Accounts and transactions already in Bow remain.")
          }
        }
      } else if isDemoMode {
        ContentUnavailableView(
          "No Sample Connection", systemImage: "arrow.clockwise",
          description: Text("Choose Sample Budget in Settings to explore bank sync examples.")
        )
      } else {
        Section {
          Text("Connect SimpleFIN, then choose the bank accounts to add to Bow.")
            .foregroundStyle(.secondary)
          NavigationLink {
            SimpleFINAccountSetupScreen()
          } label: {
            Label("Connect a Bank", systemImage: "link")
          }
        }
      }
    }
    .navigationTitle("SimpleFIN")
    .overlay {
      if coordinator.isSyncing {
        ProgressView("Contacting SimpleFIN…")
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .alert("SimpleFIN", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
    .confirmationDialog("Disconnect SimpleFIN?", isPresented: $showingDisconnect) {
      Button("Disconnect", role: .destructive) {
        do { try coordinator.disconnect(in: modelContext) }
        catch { message = error.localizedDescription }
      }
    } message: {
      Text("Every bank account will stop syncing. Existing Bow accounts and transactions remain.")
    }
  }

  private func sync() async {
    do {
      let result = try await coordinator.sync(in: modelContext, manual: true)
      message = "Added \(result.imported), matched \(result.linked), and sent \(result.needsReview) to Bank Review. \(result.pending) new pending bank items were reported."
      SimpleFINBackgroundRefresh.schedule(in: modelContext)
    } catch {
      message = error.localizedDescription
    }
  }
}
