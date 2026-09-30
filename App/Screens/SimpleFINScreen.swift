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
          VStack(alignment: .leading, spacing: Bow.Space.s4) {
            HStack(spacing: Bow.Space.s3) {
              Image(systemName: needsAttention ? "exclamationmark.triangle" : "link")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(needsAttention ? Bow.needsInk : Bow.fundedInk)
                .frame(width: 44, height: 44)
                .background(needsAttention ? Bow.needsTint : Bow.fundedTint, in: Circle())
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text(connectionStatus == "Connected" ? "SimpleFIN connected" : connectionStatus)
                  .font(.bowHeadline)
                  .foregroundStyle(Bow.ink)
                if let date = connection.lastSuccessfulAt {
                  Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.bowSubhead)
                    .foregroundStyle(Bow.inkSoft)
                }
              }
            }
            .accessibilityElement(children: .combine)
            if !isDemoMode {
              Button {
                Task { await sync() }
              } label: {
                Text("Sync now")
                  .fontWeight(.semibold)
                  .frame(maxWidth: .infinity)
              }
              .bowSecondaryButton()
              .disabled(coordinator.isSyncing)
            }
          }
          .padding(.vertical, Bow.Space.s2)
          if !isDemoMode {
            Toggle("Automatic sync", isOn: Binding(
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
          }
        } footer: {
          Text(isDemoMode
            ? "Sample bank data never contacts a real bank. Try its transaction examples in Spending."
            : "Bow checks while you use the app and requests background refresh when iOS allows it. Bank data may update about once a day.")
        }
        .listRowBackground(Bow.card)

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
            HStack(spacing: Bow.Space.s3) {
              Image(systemName: account?.kind.systemImage ?? "building.columns")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Bow.bowInk)
                .frame(width: 36, height: 36)
                .background(Bow.bowTint, in: Circle())
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text(account?.name ?? "Bow account")
                  .font(.bowBody)
                  .foregroundStyle(Bow.ink)
                Text(link.name)
                  .font(.bowFootnote).foregroundStyle(Bow.inkSoft)
                if let reportedAt = link.reportedAt {
                  Text("Bank data as of \(reportedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.bowFootnote).foregroundStyle(Bow.inkSoft)
                }
              }
              Spacer(minLength: Bow.Space.s2)
              Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Bow.fundedInk)
                .accessibilityLabel("Syncing")
            }
            .padding(.vertical, Bow.Space.s1)
            .accessibilityElement(children: .combine)
          }
          if availableCount > 0 {
            NavigationLink {
              SimpleFINAccountSetupScreen(isDemoMode: isDemoMode)
            } label: {
              Label("Add \(availableCount) found at your bank", systemImage: "plus")
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
    .bowListBackground()
    .navigationTitle("Bank sync")
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
