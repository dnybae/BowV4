import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BankFileImportScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var accounts: [BudgetAccount]
  @Query private var transactions: [BudgetTransaction]
  @Query private var payees: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
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
          if let fileName { Text(fileName).foregroundStyle(.secondary) }
        } header: {
          Text("File")
        } footer: {
          Text("Choose a CSV, OFX, QFX, or QIF export from your bank.")
        }

        Section("Account") {
          Picker("Import Into", selection: $accountID) {
            Text("Choose an account").tag(nil as UUID?)
            ForEach(accounts.sorted { $0.name < $1.name }) { account in
              Text(account.name).tag(Optional(account.id))
            }
          }
          .pickerStyle(.menu)
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
              preview()
            }
            .disabled(selectedAccount == nil)
          }
        }

        if !proposals.isEmpty {
          Section {
            Text("\(proposals.count) unique rows · \(proposals.filter { if case .review = $0.decision { true } else { false } }.count) need duplicate review")
              .font(.subheadline.weight(.medium))
          } header: {
            Text("Preview")
          } footer: {
            Text("New transactions need approval. Rows before this account’s opening date are offset in its opening balance so importing history does not change today’s cash balance.")
          }

          Section("Transactions") {
            ForEach(proposals) { proposal in
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
          Button("Import") { importFile() }
            .disabled(proposals.isEmpty || selectedAccount == nil)
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
        do {
          let url = try result.get()
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
          self.format = format
          fileName = url.lastPathComponent
          fileText = text
          csvTable = format == .csv ? try BankFileParser().csvTable(text) : nil
          if let csvTable { mapping = BankCSVMapping.suggested(for: csvTable.headers) }
          clearPreview()
        } catch {
          errorMessage = error.localizedDescription
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
    proposals = []
    importSeparately = []
  }

  private func preview() {
    guard let format, let account = selectedAccount else { return }
    do {
      let parser = BankFileParser()
      let rows: [BankImportRow]
      switch format {
      case .csv:
        guard let csvTable else { throw BankFileParseError.emptyFile }
        rows = try parser.csvRows(csvTable, mapping: mapping)
      case .ofx, .qfx:
        rows = try parser.ofxRows(fileText)
      case .qif:
        rows = try parser.qifRows(fileText, dateOrder: qifDateOrder)
      }
      let existing = transactions.filter { $0.kind != .transfer }.map {
        LocalTransactionCandidate(
          id: $0.id,
          accountID: $0.accountID,
          amountMinor: $0.amountMinor,
          date: $0.date,
          payee: $0.payee,
          externalKey: $0.externalKey,
          isManual: $0.sourceRaw == "manual"
        )
      }
      let transfers = transactions.filter { $0.kind == .transfer }.flatMap { transaction in
        var candidates = [LocalTransactionCandidate(
          id: transaction.id,
          accountID: transaction.accountID,
          amountMinor: transaction.amountMinor,
          date: transaction.date,
          payee: transaction.payee,
          externalKey: transaction.externalKey,
          isManual: false
        )]
        if let destinationID = transaction.transferAccountID {
          candidates.append(LocalTransactionCandidate(
            id: transaction.id,
            accountID: destinationID,
            amountMinor: -transaction.amountMinor,
            date: transaction.date,
            payee: transaction.payee,
            externalKey: nil,
            isManual: false
          ))
        }
        return candidates
      }
      proposals = BankImportPlanner().plan(
        rows: rows,
        accountID: account.id,
        existing: existing,
        manualTransfers: transfers
      )
      importSeparately = []
    } catch {
      clearPreview()
      errorMessage = error.localizedDescription
    }
  }

  private func importFile() {
    guard let account = selectedAccount else { return }
    do {
      _ = try BankFileImportService().save(
        proposals: proposals,
        importSeparately: importSeparately,
        account: account,
        existingTransactions: transactions,
        payees: payees,
        envelopes: envelopes,
        in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
