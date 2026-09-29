import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BankFileImportScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @Query private var accounts: [BudgetAccount]
  @Query private var profiles: [BudgetProfile]
  @Query private var payees: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var schedules: [BudgetSchedule]
  @Query(filter: #Predicate<BudgetTransaction> { $0.scheduleID != nil })
  private var scheduledTransactions: [BudgetTransaction]
  @State private var showingFilePicker = false
  @State private var fileName: String?
  @State private var fileText = ""
  @State private var format: BankFileFormat?
  @State private var csvTable: BankCSVTable?
  @State private var mapping = BankCSVMapping()
  @State private var qifDateOrder: BankDateOrder = .monthDayYear
  @State private var accountID: UUID?
  @State private var proposals: [BankImportProposal] = []
  @State private var uncategorizedManualIDs = Set<UUID>()
  @State private var manualCandidates: [UUID: LocalTransactionCandidate] = [:]
  @State private var reviewCount = 0
  @State private var visibleProposalCount = 100
  @State private var isPreviewing = false
  @State private var isImporting = false
  @State private var previewToken = UUID()
  @State private var importSummary: BankFileImportSummary?
  @State private var errorMessage: String?

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var selectedAccount: BudgetAccount? { accounts.first { $0.id == accountID } }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button("Choose Bank File", systemImage: "doc.text") {
            showingFilePicker = true
          }
          if isDemoMode {
            Button("Use Sample CSV", systemImage: "doc.text") {
              do {
                let text = DemoData.sampleBankCSV
                let table = try BankFileParser().csvTable(text)
                fileText = text
                fileName = "Demo Bank Transactions.csv"
                format = .csv
                csvTable = table
                mapping = BankCSVMapping.suggested(for: table.headers)
                accountID = accounts.first { $0.name == "Everyday Checking" }?.id ?? accounts.first?.id
                clearPreview()
              } catch {
                errorMessage = error.localizedDescription
              }
            }
          }
          if let fileName { Text(fileName).foregroundStyle(.secondary) }
        } header: {
          Text("File")
        } footer: {
          Text("Choose a CSV, OFX, QFX, or QIF export from your bank.")
        }

        Section {
          AccountSelectionField(title: "Bow Account", selection: $accountID, accounts: accounts)
        } header: {
          Text("Account")
        } footer: {
          Text("Choose the Bow account represented by this bank file.")
        }

        if format == .csv, let csvTable {
          Section("CSV Columns") {
            columnPicker("Date", selection: $mapping.dateColumn, headers: csvTable.headers)
            columnPicker("Payee", selection: $mapping.payeeColumn, headers: csvTable.headers)
            columnPicker("Memo", selection: $mapping.memoColumn, headers: csvTable.headers)
            Toggle("Separate Outflow and Inflow", isOn: $mapping.separateAmounts)
            if mapping.separateAmounts {
              columnPicker("Outflow", selection: $mapping.outflowColumn, headers: csvTable.headers)
              columnPicker("Inflow", selection: $mapping.inflowColumn, headers: csvTable.headers)
            } else {
              columnPicker("Signed Amount", selection: $mapping.amountColumn, headers: csvTable.headers)
            }
            Toggle("Reverse Amount Signs", isOn: $mapping.reverseSigns)
            Picker("Date Order", selection: $mapping.dateOrder) {
              ForEach(BankDateOrder.allCases) { order in
                Text(order.title).tag(order)
              }
            }
            .pickerStyle(.menu)
          }
        } else if format == .qif {
          Section("QIF Dates") {
            Picker("Date Order", selection: $qifDateOrder) {
              ForEach(BankDateOrder.allCases) { order in
                Text(order.title).tag(order)
              }
            }
            .pickerStyle(.menu)
          }
        }

        if format != nil {
          Section {
            Button("Preview Transactions", systemImage: "list.bullet.rectangle") {
              Task { await preview() }
            }
            .disabled(selectedAccount == nil || isPreviewing)
            if isPreviewing { ProgressView("Preparing preview…") }
            if isImporting { ProgressView("Importing transactions…") }
          }
        }

        if !proposals.isEmpty {
          Section {
            Text("\(proposals.count) rows · \(reviewCount) will go to Bank Review")
              .font(.subheadline.weight(.medium))
          } header: {
            Text("Preview")
          } footer: {
            Text("Clear matches and categorized transactions are completed automatically. Anything uncertain waits in Spending → Bank Review. Historical imports preserve today’s cash balance.")
          }

          Section("Transactions") {
            ForEach(proposals.prefix(visibleProposalCount)) { proposal in
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(proposal.row.payee.isEmpty ? "Transaction" : proposal.row.payee)
                    .fontWeight(.medium)
                  Spacer()
                  Text(BudgetMoney.formatted(proposal.row.amountMinor, currencyCode: currencyCode))
                }
                Text(proposal.row.date.formatted(date: .abbreviated, time: .omitted))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(actionLabel(for: proposal))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
            if visibleProposalCount < proposals.count {
              Button("Show More Transactions") {
                visibleProposalCount += 100
              }
            }
          }
        }
      }
      .navigationTitle("Import Bank File")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import") { Task { await importFile() } }
            .disabled(proposals.isEmpty || selectedAccount == nil || isImporting || importSummary != nil)
        }
      }
      .onChange(of: accountID) { _, _ in clearPreview() }
      .onChange(of: mapping) { _, _ in clearPreview() }
      .onChange(of: qifDateOrder) { _, _ in clearPreview() }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [
          .commaSeparatedText,
          .plainText,
          UTType(filenameExtension: "ofx") ?? .data,
          UTType(filenameExtension: "qfx") ?? .data,
          UTType(filenameExtension: "qif") ?? .data
        ]
      ) { result in handleFileSelection(result) }
      .alert("Couldn’t Import File", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .alert("Import Complete", isPresented: Binding(
        get: { importSummary != nil }, set: { if !$0 { importSummary = nil } }
      )) {
        Button("Done") { dismiss() }
      } message: {
        if let importSummary {
          Text("\(importSummary.created) added, \(importSummary.linked) matched, \(importSummary.needsReview) in Bank Review, and \(importSummary.skipped) skipped. Open Spending to review uncertain transactions.")
        }
      }
    }
  }

  private func columnPicker(
    _ title: String,
    selection: Binding<Int?>,
    headers: [String]
  ) -> some View {
    Picker(title, selection: selection) {
      Text("None").tag(nil as Int?)
      ForEach(headers.indices, id: \.self) { index in
        Text(headers[index].isEmpty ? "Column \(index + 1)" : headers[index])
          .tag(Optional(index))
      }
    }
    .pickerStyle(.menu)
  }

  private func clearPreview() {
    previewToken = UUID()
    isPreviewing = false
    proposals = []
    uncategorizedManualIDs = []
    manualCandidates = [:]
    reviewCount = 0
    visibleProposalCount = 100
    importSummary = nil
  }

  private func handleFileSelection(_ result: Result<URL, Error>) {
    Task {
      do {
        let url = try result.get()
        let loaded = try await Task.detached(priority: .userInitiated) {
          () throws -> (BankFileFormat, String, BankCSVTable?) in
          guard let format = BankFileFormat(rawValue: url.pathExtension.lowercased()) else {
            throw BankFileParseError.unsupportedFormat
          }
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }
          let data = try Data(contentsOf: url)
          let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
          guard let text else { throw BankFileParseError.unreadableText }
          let table = format == .csv ? try BankFileParser().csvTable(text) : nil
          return (format, text, table)
        }.value
        format = loaded.0
        fileName = url.lastPathComponent
        fileText = loaded.1
        csvTable = loaded.2
        if let csvTable { mapping = BankCSVMapping.suggested(for: csvTable.headers) }
        clearPreview()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func preview() async {
    guard let format, let account = selectedAccount else { return }
    let token = UUID()
    previewToken = token
    isPreviewing = true
    defer { if previewToken == token { isPreviewing = false } }
    do {
      let sourceText = fileText
      let table = csvTable
      let selectedMapping = mapping
      let selectedDateOrder = qifDateOrder
      let rows = try await Task.detached(priority: .userInitiated) { () throws -> [BankImportRow] in
        let parser = BankFileParser()
        switch format {
        case .csv:
          guard let table else { throw BankFileParseError.emptyFile }
          return try parser.csvRows(table, mapping: selectedMapping)
        case .ofx, .qfx:
          return try parser.ofxRows(sourceText)
        case .qif:
          return try parser.qifRows(sourceText, dateOrder: selectedDateOrder)
        }
      }.value
      let accountID = account.id
      let bundle = try await BankImportCandidateRepository(modelContainer: modelContext.container)
        .candidates(accountID: accountID, rows: rows)
      let planned = await Task.detached(priority: .userInitiated) {
        BankImportPlanner().plan(
          rows: rows, accountID: accountID,
          existing: bundle.existing, manualTransfers: bundle.transfers,
          stagedKeys: bundle.stagedKeys
        )
      }.value
      guard previewToken == token else { return }
      proposals = planned
      uncategorizedManualIDs = bundle.uncategorizedManualIDs
      manualCandidates = Dictionary(uniqueKeysWithValues: bundle.existing.map { ($0.id, $0) })
      reviewCount = planned.filter(needsReview).count
      visibleProposalCount = 100
    } catch {
      guard previewToken == token else { return }
      clearPreview()
      errorMessage = error.localizedDescription
    }
  }

  private func importFile() async {
    guard let account = selectedAccount else { return }
    guard !isImporting else { return }
    isImporting = true
    defer { isImporting = false }
    do {
      importSummary = try await BankFileImportRepository(modelContainer: modelContext.container).save(
        proposals: proposals,
        accountID: account.id
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func needsReview(_ proposal: BankImportProposal) -> Bool {
    guard let account = selectedAccount else { return false }
    if case .alreadyImported = proposal.decision { return false }
    if schedules.contains(where: { schedule in
      guard schedule.isActive && schedule.kind == .transfer,
            ScheduleRecurrence().occurs(
              starting: schedule.startDate, frequency: schedule.frequency,
              on: proposal.row.date
            ) else { return false }
      return (schedule.accountID == account.id && proposal.row.amountMinor == -schedule.amountMinor)
        || (schedule.transferAccountID == account.id && proposal.row.amountMinor == schedule.amountMinor)
    }) { return true }
    let scheduled = schedules.filter { schedule in
      schedule.isActive && schedule.kind == .expense
        && schedule.accountID == account.id
        && proposal.row.amountMinor == -schedule.amountMinor
        && schedule.payee.localizedCaseInsensitiveCompare(proposal.row.payee) == .orderedSame
        && ScheduleRecurrence().occurs(
          starting: schedule.startDate, frequency: schedule.frequency,
          on: proposal.row.date
        )
    }
    if scheduled.count > 1 { return true }
    switch proposal.decision {
    case .alreadyImported: return false
    case .linkManual(let id):
      if uncategorizedManualIDs.contains(id) { return true }
      if let schedule = scheduled.first, let manual = manualCandidates[id] {
        return (manual.scheduleID != nil && manual.scheduleID != schedule.id)
          || (schedule.envelopeID != nil && manual.envelopeID != schedule.envelopeID)
      }
      return false
    case .review: return true
    case .createNew:
      if proposal.row.amountMinor >= 0 { return false }
      if let schedule = scheduled.first,
         scheduledTransactions.contains(where: { transaction in
           transaction.scheduleID == schedule.id
             && transaction.scheduledFor.map {
               Calendar.current.isDate($0, inSameDayAs: proposal.row.date)
             } == true
         }) { return true }
      if scheduled.count == 1 && scheduled[0].envelopeID != nil { return false }
      let ids = Set(envelopes.filter { !$0.isHidden && $0.paymentAccountID == nil }.map(\.id))
      let rules = PayeeDirectory.ruleItems(payees: payees, validEnvelopeIDs: ids)
      return PayeeRuleMatcher().envelopeID(for: proposal.row.payee, rules: rules) == nil
    }
  }

  private func actionLabel(for proposal: BankImportProposal) -> String {
    if needsReview(proposal) { return "Bank Review · choose a match or envelope" }
    switch proposal.decision {
    case .alreadyImported: return "Already in Bow · skipped"
    case .linkManual: return "Matches your existing entry"
    case .createNew: return "Adds automatically"
    case .review: return "Bank Review"
    }
  }
}
