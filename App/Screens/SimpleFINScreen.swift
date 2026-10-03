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
  @State private var showingSetup = false
  @Environment(\.bowToasts) private var toasts

  private var connection: SimpleFINConnection? { connections.first }
  private var linkedAccounts: [SimpleFINAccountLink] {
    links.filter { $0.localAccountID != nil }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  private var availableCount: Int { links.filter { $0.localAccountID == nil }.count }
  private var connectionStatus: ConnectionStatus {
    if isDemoMode { return .sample }
    if linkedAccounts.isEmpty { return .noAccounts }
    if let connection, let attempted = connection.lastAttemptAt,
       attempted > (connection.lastSuccessfulAt ?? .distantPast),
       connection.lastMessage != nil {
      return .needsAttention
    }
    return .connected
  }

  private var needsAttention: Bool { connectionStatus == .needsAttention }

  var body: some View {
    Form {
      if let connection {
        Section {
          VStack(spacing: Bow.Space.s4) {
            BowIdentityHeader(
              name: "SimpleFIN",
              context: coordinator.isSyncing ? nil : connection.lastSuccessfulAt.map {
                "Last synced \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
              } ?? connectionStatus.title,
              pill: needsAttention ? StatusPill(text: "Sync needs attention", state: .needs)
                : isDemoMode ? StatusPill(text: "Sample connection", state: .empty) : nil
            ) {
              BowGlossyTile(systemImage: needsAttention ? "exclamationmark.triangle" : "link")
            }
            if coordinator.isSyncing {
              BowLoadingLabel("Syncing with your bank…")
                .transition(.opacity)
            }
            if !isDemoMode {
              Button(coordinator.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await sync() }
              }
              .symbolEffect(.rotate, isActive: coordinator.isSyncing)
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
              .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        } else {
          Section {
          } footer: {
            Text("Sample bank data never contacts a real bank. Try its transaction examples in Spending.")
              .font(.bowFootnote)
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
              .font(.bowBody)
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
              AccountLogoView(appearance: account?.logoAppearance ?? link.logoAppearance,
                              systemImage: account?.accountType.systemImage ?? "building.columns", size: 28)
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
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)

        if !isDemoMode {
          Section {
            Button("Disconnect SimpleFIN", role: .destructive) {
              showingDisconnect = true
            }
          } footer: {
            Text("This stops sync for every linked account. Accounts and transactions already in Bow remain.")
              .font(.bowFootnote)
          }
          .listRowBackground(Bow.card)
        }
      } else if isDemoMode {
        ContentUnavailableView(
          "No sample connection", systemImage: "arrow.clockwise",
          description: Text("Choose Sample Budget in Settings to explore bank sync examples.")
        )
      } else {
        BowFeatureIntro(
          systemImage: "building.columns",
          title: "Bring in transactions automatically",
          points: [
            .init(systemImage: "arrow.triangle.2.circlepath", text: "Bow checks your bank about once a day."),
            .init(systemImage: "tray", text: "New items wait in Spending for you to approve."),
            .init(systemImage: "lock", text: "Your bank login stays with SimpleFIN, never with Bow.")
          ],
          actionTitle: "Connect a bank"
        ) {
          showingSetup = true
        }
        .listRowBackground(Color.clear)
      }
    }
    .bowListBackground()
    .navigationTitle("Bank sync")
    .navigationBarTitleDisplayMode(.inline)
    .bowAnimation(value: coordinator.isSyncing)
    .navigationDestination(isPresented: $showingSetup) {
      SimpleFINAccountSetupScreen()
    }
    .bowErrorAlert("SimpleFIN", message: $message)
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
      toasts?.show(BowToast(
        message: result.imported + result.linked + result.needsReview == 0
          ? "Up to date. Nothing new from your bank."
          : "Added \(result.imported) · Matched \(result.linked) · \(result.needsReview) to review",
        systemImage: "checkmark.circle.fill"
      ))
      SimpleFINBackgroundRefresh.schedule(in: modelContext)
    } catch {
      message = error.localizedDescription
    }
  }
}

private enum ConnectionStatus {
  case sample, noAccounts, needsAttention, connected

  var title: String {
    switch self {
    case .sample: "Sample connection"
    case .noAccounts: "No accounts syncing"
    case .needsAttention: "Sync needs attention"
    case .connected: "Connected"
    }
  }
}
