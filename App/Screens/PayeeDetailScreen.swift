import SwiftUI
import SwiftData

struct PayeeDetailScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var schedules: [BudgetSchedule]
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var profiles: [BudgetProfile]
  var payeeKey: String
  @State private var showingEdit = false
  @State private var selectedTransaction: BudgetTransaction?
  @State private var selectedSchedule: BudgetSchedule?
  @State private var entry: PayeeDirectory.Entry?
  @State private var hasLoadedEntry = false
  @State private var feed = TransactionFeedModel()
  @State private var activity: PayeeActivity?
  @State private var activityVersion = 0
  @State private var reloadVersion = 0
  @State private var showingMerge = false
  @State private var scheduleDraft: ScheduleDraft?

  private var payee: BudgetPayee? {
    guard let ruleID = entry?.ruleID else { return nil }
    return payees.first { $0.id == ruleID }
  }

  private var usualAccountName: String? {
    guard let id = activity?.usualAccountID else { return nil }
    return accounts.first { $0.id == id }?.name
  }

  private var websiteURL: URL? {
    guard let domain = payee?.merchantDomain, !domain.isEmpty else { return nil }
    return URL(string: "https://\(domain)")
  }

  private var webSearchURL: URL? {
    guard let name = entry?.name else { return nil }
    var components = URLComponents(string: "https://www.google.com/search")
    components?.queryItems = [URLQueryItem(name: "q", value: name)]
    return components?.url
  }

  private var matchingSchedules: [BudgetSchedule] {
    schedules.filter {
      PayeeDirectory.canonicalKey(for: $0.payee, payees: payees) == payeeKey
    }.sorted { $0.startDate < $1.startDate }
  }

  private var activeExpenseSchedules: [BudgetSchedule] {
    matchingSchedules.filter { $0.isActive && $0.kind == .expense }
  }

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  private func makeScheduleDraft(for recurrence: PayeeRecurrence, name: String) -> ScheduleDraft {
    let usableEnvelopeIDs = Set(envelopes.filter { !$0.isHidden && $0.paymentAccountID == nil }.map(\.id))
    let envelopeID = [recurrence.envelopeID, payee?.defaultEnvelopeID]
      .compactMap { $0 }
      .first { usableEnvelopeIDs.contains($0) }
    return ScheduleDraft(
      payee: name,
      amountMinor: recurrence.amountMinor,
      accountID: accounts.first { $0.id == recurrence.accountID }?.id,
      envelopeID: envelopeID,
      startDate: recurrence.nextDate,
      frequency: recurrence.frequency
    )
  }

  /// Default envelope, bank names, notes and links out.
  @ViewBuilder
  private func aboutSection(_ entry: PayeeDirectory.Entry) -> some View {
    let bankNames = payee?.bankNames ?? []
    let defaultEnvelope = payee.flatMap { payee in envelopes.first { $0.id == payee.defaultEnvelopeID } }
    let notes = payee?.notes ?? ""
    if defaultEnvelope != nil || !bankNames.isEmpty || !notes.isEmpty || websiteURL != nil || webSearchURL != nil {
      Section {
        if let defaultEnvelope {
          BowTileValueRow("Default envelope", systemImage: "square.grid.2x2", value: defaultEnvelope.name)
        }
        if !bankNames.isEmpty {
          NavigationLink {
            PayeeBankNamesScreen(payeeName: entry.name, bankNames: bankNames)
          } label: {
            BowTileValueRow(title: "Bank names", systemImage: "building.columns") {
              Text(bankNames.count == 1 ? bankNames[0] : "\(bankNames[0]) +\(bankNames.count - 1)")
                .lineLimit(1)
            }
          }
        }
        if !notes.isEmpty {
          Label {
            Text(notes)
              .foregroundStyle(Bow.ink)
              .textSelection(.enabled)
          } icon: {
            Image(systemName: "note.text")
          }
          .labelStyle(.bowTile)
        }
        if let websiteURL {
          Link(destination: websiteURL) {
            Label("Visit \(websiteURL.host() ?? "website")", systemImage: "safari").labelStyle(.bowTile)
          }
        }
        if let webSearchURL {
          Link(destination: webSearchURL) {
            Label("Search this payee on the web", systemImage: "globe").labelStyle(.bowTile)
          }
        }
      } header: {
        Text("About")
      } footer: {
        if !bankNames.isEmpty {
          Text("Imported transactions with these descriptions are filed under \(entry.name).")
        }
      }
      .listRowBackground(Bow.card)
    }
  }

  var body: some View {
    List {
      if let entry {
        Section {
          VStack(spacing: Bow.Space.s4) {
            BowIdentityHeader(
              name: entry.name,
              context: usualAccountName.map { "Usually paid with \($0)" }
            ) {
              MerchantLogoView(merchantName: entry.name, domain: payee?.merchantDomain,
                               size: 64, style: .glossy)
            }
            if let activity {
              BowStatStrip(stats: activity.stats(currencyCode: currencyCode), currencyCode: currencyCode)
            }
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Bow.Space.s2, trailing: 0))
        }
        aboutSection(entry)
        if let activity {
          PayeeActivitySection(activity: activity)
          if let recurrence = activity.recurrence {
            PayeeRecurrenceSection(
              recurrence: recurrence,
              existingSchedule: activeExpenseSchedules.count == 1 ? activeExpenseSchedules.first : nil,
              hasOtherSchedules: activeExpenseSchedules.count > 1,
              currencyCode: currencyCode,
              onCreateSchedule: { scheduleDraft = makeScheduleDraft(for: recurrence, name: entry.name) },
              onEditSchedule: { selectedSchedule = $0 }
            )
          }
        }
        if !matchingSchedules.isEmpty {
          Section("Scheduled") {
            ForEach(matchingSchedules) { schedule in
              Button {
                selectedSchedule = schedule
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(schedule.payee).foregroundStyle(Bow.ink)
                    Text(schedule.frequency.title)
                      .font(.subheadline)
                      .foregroundStyle(Bow.inkSoft)
                  }
                  Spacer()
                  MoneyText(minor: schedule.amountMinor, currencyCode: currencyCode)
                    .foregroundStyle(Bow.inkSoft)
                    .fontDesign(.rounded).monospacedDigit()
                }
              }
            }
          }
          .listRowBackground(Bow.card)
        }
        if !entry.isTransferOnly {
          Section {
            Button("Merge a duplicate payee…", systemImage: "arrow.triangle.merge") {
              showingMerge = true
            }
          } footer: {
            Text("Combine payees that are really the same place, like “Target” and “Target.com”.")
          }
          .listRowBackground(Bow.card)
        }
        if feed.items.isEmpty && !feed.isLoading {
          ContentUnavailableView(
            "No transactions yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Transactions for this payee will appear here.")
          )
        } else {
          ForEach(Array(TransactionDateGroup.make(feed.items).enumerated()), id: \.element.id) { index, group in
            Section {
              ForEach(group.items) { transaction in
                Button {
                  let id = transaction.id
                  let predicate = #Predicate<BudgetTransaction> { $0.id == id }
                  selectedTransaction = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first
                } label: {
                  TransactionRowView(
                    model: TransactionRowModel(transaction), currencyCode: currencyCode
                  )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens transaction details")
              }
            } header: {
              // The first day sits under an Activity heading.
              if index == 0 {
                VStack(alignment: .leading, spacing: Bow.Space.s2) {
                  Text("Activity")
                  Text(group.title)
                }
              } else {
                Text(group.title)
              }
            }
            .listRowBackground(Bow.card)
          }
          if feed.hasMore {
            ProgressView("Loading more…")
              .frame(maxWidth: .infinity)
              .onAppear { Task { await feed.loadNext() } }
          }
        }
      } else if hasLoadedEntry {
        ContentUnavailableView(
          "Payee Not Found", systemImage: "person.crop.circle.badge.questionmark",
          description: Text("It may have been merged with another payee or renamed.")
        )
        .listRowBackground(Color.clear)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }
    }
    .bowSkyList(mood: .dawn, height: 460)
    .navigationTitle("Payee")
    .task(id: "\(payeeKey)|\(reloadVersion)") {
      let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
      entry = (try? await repository.entries())?.first { $0.key == payeeKey }
      hasLoadedEntry = true
      await feed.reload(container: modelContext.container, searchText: "",
                        filter: TransactionFilter(), scopedPayeeKey: payeeKey,
                        includeUncategorizedCount: false)
    }
    .task(id: activityVersion) {
      let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
      activity = try? await repository.activity(for: payeeKey)
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      activityVersion += 1
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { showingEdit = true }
          .disabled(entry == nil)
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let entry {
        PayeeEditorScreen(entry: entry, payee: payee) { dismiss() }
      }
    }
    .navigationDestination(item: $selectedTransaction) { transaction in
      TransactionDetailScreen(
        transaction: transaction,
        accounts: accounts, envelopes: envelopes,
        payees: payees, currencyCode: currencyCode
      )
      // Opening this payee again from its own transaction would only loop.
      .environment(\.currentPayeeKey, payeeKey)
    }
    .sheet(isPresented: $showingMerge) {
      if let entry {
        PayeeMergeSheet(target: entry) { reloadVersion += 1 }
      }
    }
    .sheet(item: $scheduleDraft) { draft in
      ScheduleEditorScreen(
        schedule: nil,
        draft: draft,
        accounts: accounts,
        envelopes: envelopes,
        currencyCode: currencyCode
      )
    }
    .sheet(item: $selectedSchedule) { schedule in
      ScheduleEditorScreen(
        schedule: schedule,
        accounts: accounts,
        envelopes: envelopes,
        currencyCode: currencyCode
      )
    }
  }
}

/// Every bank description filed under a payee, selectable for copying.
private struct PayeeBankNamesScreen: View {
  var payeeName: String
  var bankNames: [String]

  var body: some View {
    List {
      Section {
        ForEach(bankNames, id: \.self) { bankName in
          Text(bankName)
            .foregroundStyle(Bow.ink)
            .textSelection(.enabled)
        }
      } footer: {
        Text("Imported transactions with these descriptions are filed under \(payeeName).")
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle("Bank names")
    .navigationBarTitleDisplayMode(.inline)
  }
}
