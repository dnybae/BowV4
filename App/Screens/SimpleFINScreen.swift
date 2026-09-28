import SwiftUI
import SwiftData

struct SimpleFINScreen: View {
  var onDone: (() -> Void)? = nil
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @Query private var connections: [SimpleFINConnection]
  @Query private var links: [SimpleFINAccountLink]
  @Query private var records: [SimpleFINImportRecord]
  @Query private var accounts: [BudgetAccount]
  @State private var coordinator = SimpleFINSyncCoordinator.shared
  @State private var setupToken = ""
  @State private var chooseImportDate = false
  @State private var importDate = Date().addingTimeInterval(-89 * 86_400)
  @State private var message: String?
  @State private var showingDisconnect = false

  private var connection: SimpleFINConnection? { connections.first }
  private var reviewItems: [SimpleFINImportRecord] {
    records.filter { $0.status == .review }.sorted { $0.date > $1.date }
  }

  var body: some View {
    Form {
      if let connection {
        Section {
          LabeledContent("Status", value: isDemoMode ? "Demo connection" : "Connected")
          if let date = connection.lastSuccessfulAt {
            LabeledContent("Last sync", value: date.formatted(date: .abbreviated, time: .shortened))
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
                  message = "Automatic sync could not be updated: \(error.localizedDescription)"
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
            ? "This sample connection never contacts a bank. Review the example matches below or change account mappings to test the interface."
            : "Bow checks while you use the app and requests background refresh when iOS allows it. SimpleFIN may update a bank only once a day.")
        }

        if let lastMessage = connection.lastMessage, !lastMessage.isEmpty {
          Section("SimpleFIN Messages") {
            Text(lastMessage)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          if links.isEmpty {
            Text("No bank accounts were returned. Sync again after connecting accounts in SimpleFIN.")
              .foregroundStyle(.secondary)
          }
          ForEach(links.sorted { $0.name < $1.name }) { link in
            VStack(alignment: .leading, spacing: 4) {
              AccountSelectionField(title: link.name, selection: Binding(
                get: { link.localAccountID },
                set: { id in setMapping(id, for: link, connection: connection) }
              ), accounts: accounts.filter { account in
                  account.currencyCode == link.currencyCode
                    && (account.id == link.localAccountID
                      || !links.contains { $0.id != link.id && $0.localAccountID == account.id })
                }, noneTitle: "Do Not Import")
              if let balance = link.reportedBalance, let date = link.reportedAt {
                Text("Bank balance: \(balance) \(link.currencyCode) · \(date.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            if link.localAccountID == nil && !isDemoMode {
              NavigationLink {
                AccountEditorScreen(
                  currencyCode: link.currencyCode,
                  suggestedName: link.name,
                  suggestedBalanceMinor: link.reportedBalance.flatMap {
                    BudgetMoney.parseMinor($0, locale: Locale(identifier: "en_US_POSIX"))
                  }
                ) { account in
                  setMapping(account.id, for: link, connection: connection)
                }
              } label: {
                Label("Create and Link \(link.name)", systemImage: "plus")
              }
            }
          }
        } header: {
          Text("Import Into Bow")
        } footer: {
          Text(isDemoMode
            ? "Try changing these mappings. The sample review items stay with their original accounts; in a connected budget, a mapping change affects future imports."
            : "Create a Bow account or choose an existing one with the same currency, then tap Sync Now. Unlinked bank accounts are skipped. Changing a link affects future imports only.")
        }

        if !reviewItems.isEmpty {
          Section("Possible Duplicates · \(reviewItems.count)") {
            ForEach(reviewItems) { record in
              NavigationLink {
                SimpleFINReviewScreen(record: record)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(record.payee.isEmpty ? "Bank transaction" : record.payee)
                  Text("\(record.date.formatted(date: .abbreviated, time: .omitted)) · \(BudgetMoney.formatted(record.amountMinor, currencyCode: accounts.first { $0.id == record.localAccountID }?.currencyCode ?? "USD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        if !isDemoMode {
          Section {
            Button("Disconnect SimpleFIN", role: .destructive) { showingDisconnect = true }
          } footer: {
            Text("Disconnecting stops future imports. Transactions already in Bow remain. You can also revoke access in SimpleFIN.")
          }
        }
      } else if isDemoMode {
        Section {
          ContentUnavailableView(
            "No Sample Connection",
            systemImage: "arrow.clockwise",
            description: Text("Choose Sample Budget in Settings to explore bank mappings and duplicate review.")
          )
        }
      } else {
        Section {
          Text("Connect a read-only bank feed, then choose which bank accounts to add to Bow.")
            .foregroundStyle(.secondary)
          Link("Get a SimpleFIN Setup Token", destination: URL(string: "https://bridge.simplefin.org/simplefin/create")!)
          SecureField("Setup Token", text: $setupToken)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
          Toggle("Choose import start date", isOn: $chooseImportDate)
          if chooseImportDate {
            DatePicker("Import From", selection: $importDate,
                       in: Date().addingTimeInterval(-89 * 86_400)...Date(),
                       displayedComponents: .date)
          }
          Button("Connect SimpleFIN", systemImage: "link") {
            Task { await connect() }
          }
          .disabled(setupToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isSyncing)
        } header: {
          Text("Connect")
        } footer: {
          Text("Leave the date off to request available history from the last 90 days. SimpleFIN has a separate signup and fee. Bow stores the access credential securely on this device.")
        }
      }
    }
    .navigationTitle("SimpleFIN")
    .toolbar {
      if connection != nil, let onDone {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
    .overlay {
      if coordinator.isSyncing {
        ProgressView("Contacting SimpleFIN…")
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .alert("SimpleFIN", isPresented: Binding(
      get: { message != nil },
      set: { if !$0 { message = nil } }
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
      Text("Bank transactions already imported into Bow will remain.")
    }
  }

  private func connect() async {
    do {
      try await coordinator.connect(
        token: setupToken,
        startDate: chooseImportDate ? Calendar.current.startOfDay(for: importDate) : nil,
        in: modelContext
      )
      setupToken = ""
      SimpleFINBackgroundRefresh.schedule(in: modelContext)
    } catch {
      setupToken = ""
      message = error.localizedDescription
    }
  }

  private func setMapping(_ id: UUID?, for link: SimpleFINAccountLink,
                          connection: SimpleFINConnection) {
    let previousID = link.localAccountID
    let previousChange = connection.lastMappingChangeAt
    link.localAccountID = id
    connection.lastMappingChangeAt = Date()
    do {
      try modelContext.save()
    } catch {
      link.localAccountID = previousID
      connection.lastMappingChangeAt = previousChange
      message = "Account link could not be updated: \(error.localizedDescription)"
    }
  }

  private func sync() async {
    do {
      let result = try await coordinator.sync(in: modelContext, manual: true)
      message = "Imported \(result.imported), matched \(result.linked), and held \(result.needsReview) for duplicate review."
      SimpleFINBackgroundRefresh.schedule(in: modelContext)
    } catch {
      message = error.localizedDescription
    }
  }
}
