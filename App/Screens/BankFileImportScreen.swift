import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BankFileImportScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  @Query private var accounts: [BudgetAccount]
  @Query private var profiles: [BudgetProfile]
  @State private var showingFilePicker = false
  @State private var fileName: String?
  @State private var fileText = ""
  @State private var format: BankFileFormat?
  @State private var csvTable: BankCSVTable?
  @State private var mapping = BankCSVMapping()
  @State private var qifDateOrder: BankDateOrder = .monthDayYear
  @State private var accountID: UUID?
  @State private var proposals: [BankImportProposal] = []
  @State private var reviewCount = 0
  @State private var visibleProposalCount = 100
  @State private var isPreviewing = false
  @State private var isImporting = false
  @State private var previewToken = UUID()
  @State private var importSeparately: Set<String> = []
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

        Section("Account") {
          AccountSelectionField(title: "Import Into", selection: $accountID, accounts: accounts)
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
            Text("\(proposals.count) unique rows · \(reviewCount) need duplicate review")
              .font(.subheadline.weight(.medium))
          } header: {
            Text("Preview")
          } footer: {
            Text("New transactions need approval. Rows before this account’s opening date are offset in its opening balance so importing history does not change today’s cash balance.")
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
                switch proposal.decision {
                case .createNew:
                  Text("New · needs approval")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .linkManual:
                  Text("Links your manual transaction")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .alreadyImported:
                  Text("Already imported · skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .review:
                  Toggle("Import separately (possible duplicate)", isOn: Binding(
                    get: { importSeparately.contains(proposal.externalKey) },
                    set: { enabled in
                      if enabled {
                        importSeparately.insert(proposal.externalKey)
                      } else {
                        importSeparately.remove(proposal.externalKey)
                      }
                    }
                  ))
                  .font(.caption)
                }
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
            .disabled(proposals.isEmpty || selectedAccount == nil || isImporting)
        }
      }
      .onAppear {
        if accountID == nil { accountID = accounts.first?.id }
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
      ) { result in
        Task {
          do {
            let url = try result.get()
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> (BankFileFormat, String, BankCSVTable?) in
              guard let format = BankFileFormat(rawValue: url.pathExtension.lowercased()) else {
                throw BankFileParseError.unsupportedFormat
              }
              let accessed = url.startAccessingSecurityScopedResource()
              defer { if accessed { url.stopAccessingSecurityScopedResource() } }
              let data = try Data(contentsOf: url)
              guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw BankFileParseError.unreadableText
              }
              return (format, text, format == .csv ? try BankFileParser().csvTable(text) : nil)
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
      .alert("Couldn’t Import File", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
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
    reviewCount = 0
    visibleProposalCount = 100
    importSeparately = []
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
          existing: bundle.existing, manualTransfers: bundle.transfers
        )
      }.value
      guard previewToken == token else { return }
      proposals = planned
      reviewCount = planned.reduce(0) { count, proposal in
        if case .review = proposal.decision { count + 1 } else { count }
      }
      visibleProposalCount = 100
      importSeparately = []
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
      _ = try await BankFileImportRepository(modelContainer: modelContext.container).save(
        proposals: proposals,
        importSeparately: importSeparately,
        accountID: account.id
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
