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

  var body: some View {
    List {
      if let entry {
        Section("Icon") {
          HStack(spacing: 12) {
            MerchantLogoView(merchantName: entry.name,
                             domain: payee?.merchantDomain,
                             size: 52)
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.name).font(.headline)
              Text(payee?.logoSource.title ?? "Default icon")
                .font(.subheadline).foregroundStyle(Bow.inkSoft)
            }
          }
        }
        .listRowBackground(Bow.card)
        if let activity {
          PayeeActivitySection(
            activity: activity, usualAccountName: usualAccountName, currencyCode: currencyCode
          )
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
                      .font(.caption)
                      .foregroundStyle(Bow.inkSoft)
                  }
                  Spacer()
                  Text(BudgetMoney.formatted(schedule.amountMinor, currencyCode: currencyCode))
                    .foregroundStyle(Bow.inkSoft)
                    .fontDesign(.rounded).monospacedDigit()
                }
              }
            }
          }
          .listRowBackground(Bow.card)
        }
        if let payee,
           let envelope = envelopes.first(where: { $0.id == payee.defaultEnvelopeID }) {
          Section("Default envelope") {
            LabeledContent("Envelope", value: envelope.name)
          }
          .listRowBackground(Bow.card)
        }
        Section("About") {
          if let notes = payee?.notes, !notes.isEmpty {
            Text(notes)
              .foregroundStyle(Bow.ink)
              .textSelection(.enabled)
          }
          if let websiteURL {
            Link(destination: websiteURL) {
              Label("Visit \(websiteURL.host() ?? "website")", systemImage: "safari")
            }
          } else if let webSearchURL {
            Link(destination: webSearchURL) {
              Label("Search the web", systemImage: "magnifyingglass")
            }
          }
        }
        .listRowBackground(Bow.card)
        if let bankNames = payee?.bankNames, !bankNames.isEmpty {
          Section {
            ForEach(bankNames, id: \.self) { bankName in
              Text(bankName)
                .foregroundStyle(Bow.ink)
                .textSelection(.enabled)
            }
          } header: {
            Text("Bank names")
          } footer: {
            Text("Imported transactions with these descriptions are filed under \(entry.name).")
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
          ForEach(TransactionDateGroup.make(feed.items)) { group in
            Section(group.title) {
              ForEach(group.items) { transaction in
                Button {
                  let id = transaction.id
                  let predicate = #Predicate<BudgetTransaction> { $0.id == id }
                  selectedTransaction = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first
                } label: {
                  TransactionSummaryRow(
                    transaction: transaction, currencyCode: currencyCode, showsDate: false
                  )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open transaction")
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
      }
    }
    .bowListBackground()
    .navigationTitle(entry?.name ?? "Payee")
    .task(id: "\(payeeKey)|\(reloadVersion)") {
      let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
      entry = (try? await repository.entries())?.first { $0.key == payeeKey }
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
    .sheet(item: $selectedTransaction) { transaction in
      TransactionEditorScreen(
        transaction: transaction,
        accounts: accounts,
        envelopes: envelopes,
        payees: payees,
        currencyCode: currencyCode
      )
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
