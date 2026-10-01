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

  private var needsAttention: Bool { connectionStatus == "Sync needs attention" }

  var body: some View {
    Form {
      if let connection {
        Section {
          VStack(spacing: Bow.Space.s4) {
            BowIdentityHeader(
              name: "SimpleFIN",
              context: connection.lastSuccessfulAt.map {
                "Last synced \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
              } ?? connectionStatus,
              pill: needsAttention ? StatusPill(text: "Sync needs attention", state: .needs)
                : isDemoMode ? StatusPill(text: "Sample connection", state: .empty) : nil
            ) {
              BowGlossyTile(systemImage: needsAttention ? "exclamationmark.triangle" : "link")
            }
            if !isDemoMode {
              Button("Sync now") {
                Task { await sync() }
              }
              .fontWeight(.semibold)
              .bowSecondaryButton()
              .disabled(coordinator.isSyncing)
            }
          }
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
        }

        if !isDemoMode {
          Section {
            Toggle(isOn: Binding(
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
            )) {
              Label("Automatic sync", systemImage: "arrow.triangle.2.circlepath").labelStyle(.bowTile)
            }
          } footer: {
            Text("Bow checks while you use the app and requests background refresh when iOS allows it. Bank data may update about once a day.")
          }
          .listRowBackground(Bow.card)
        } else {
          Section {
          } footer: {
            Text("Sample bank data never contacts a real bank. Try its transaction examples in Spending.")
          }
        }

        if let lastMessage = connection.lastMessage, !lastMessage.isEmpty {
          Section("Connection message") {
            Text(lastMessage).foregroundStyle(Bow.inkSoft)
          }
          .listRowBackground(Bow.card)
        }

        Section {
          if linkedAccounts.isEmpty {
            Text("No bank accounts have been added to Bow yet.")
              .foregroundStyle(Bow.inkSoft)
          }
          ForEach(linkedAccounts) { link in
            let account = accounts.first { $0.id == link.localAccountID }
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(account?.name ?? "Bow account")
                  .foregroundStyle(Bow.ink)
                Text(link.name)
                  .font(.bowSubhead).foregroundStyle(Bow.inkSoft)
                if let reportedAt = link.reportedAt {
                  Text("Bank data as of \(reportedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.bowSubhead).foregroundStyle(Bow.inkSoft)
                }
              }
            } icon: {
              Image(systemName: account?.kind.systemImage ?? "building.columns")
            }
            .labelStyle(.bowTile)
            .padding(.vertical, Bow.Space.s1)
            .accessibilityElement(children: .combine)
            .accessibilityValue("Syncing")
          }
          if availableCount > 0 {
            NavigationLink {
              SimpleFINAccountSetupScreen(isDemoMode: isDemoMode)
            } label: {
              Label("Add \(availableCount) found at your bank", systemImage: "plus")
                .labelStyle(.bowTile)
                .foregroundStyle(Bow.bowInk)
            }
          }
        } header: {
          Text("Syncing with Bow")
        } footer: {
          Text("To stop syncing an account, open it from Accounts.")
        }
        .listRowBackground(Bow.card)

        if !isDemoMode {
          Section {
            Button("Disconnect SimpleFIN", role: .destructive) {
              showingDisconnect = true
            }
          } footer: {
            Text("This stops sync for every linked account. Accounts and transactions already in Bow remain.")
          }
          .listRowBackground(Bow.card)
        }
      } else if isDemoMode {
        ContentUnavailableView(
          "No sample connection", systemImage: "arrow.clockwise",
          description: Text("Choose Sample Budget in Settings to explore bank sync examples.")
        )
      } else {
        Section {
          Text("Connect SimpleFIN, then choose the bank accounts to add to Bow.")
            .foregroundStyle(Bow.inkSoft)
          NavigationLink {
            SimpleFINAccountSetupScreen()
          } label: {
            Label("Connect a bank", systemImage: "link")
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowSkyList(mood: needsAttention ? .review : .dawn, height: 460)
    .navigationTitle("Bank sync")
    .navigationBarTitleDisplayMode(.inline)
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
