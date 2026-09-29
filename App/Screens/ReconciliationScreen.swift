import SwiftUI
import SwiftData

struct ReconciliationScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var account: BudgetAccount
  var currencyCode: String
  @State private var entries: [ReconciliationEntry] = []
  @State private var payeeNames: [UUID: String] = [:]
  @State private var clearedBalanceMinor: Int64 = 0
  @State private var statementDate = Date()
  @State private var statementBalance = ""
  @State private var selectedIDs: Set<UUID> = []
  @State private var visibleEntryCount = 300
  @State private var isFinishing = false
  @State private var errorMessage: String?

  private var calculator: ReconciliationCalculator { ReconciliationCalculator() }
  private var enteredBalance: Int64? { BudgetMoney.parseMinor(statementBalance) }
  private var difference: Int64? { enteredBalance.map { $0 - clearedBalanceMinor } }

  var body: some View {
    NavigationStack {
      List {
        Section {
          DatePicker("Statement date", selection: $statementDate, in: ...Date(), displayedComponents: .date)
          TextField("Statement balance", text: $statementBalance)
            .keyboardType(.numbersAndPunctuation)
        } header: {
          Text("Statement")
        } footer: {
          Text("Enter the balance shown by your bank on the statement date.")
        }
        Section("Difference") {
          LabeledContent("Cleared balance", value: BudgetMoney.formatted(clearedBalanceMinor, currencyCode: currencyCode))
          if let difference {
            LabeledContent("Difference", value: BudgetMoney.formatted(difference, currencyCode: currencyCode))
              .foregroundStyle(difference == 0 ? .green : .orange)
          } else {
            Text("Enter a statement balance to compare.")
              .foregroundStyle(.secondary)
          }
        }
        Section {
          if entries.isEmpty {
            ContentUnavailableView("No entries by this date", systemImage: "list.bullet.rectangle")
          } else {
            ForEach(entries.prefix(visibleEntryCount)) { entry in
              Button {
                if selectedIDs.insert(entry.id).inserted {
                  clearedBalanceMinor += entry.amountMinor
                } else {
                  selectedIDs.remove(entry.id)
                  clearedBalanceMinor -= entry.amountMinor
                }
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(entry.id) ? Color.accentColor : Color.secondary)
                    .font(.title3)
                  VStack(alignment: .leading) {
                    Text(payeeNames[entry.id].flatMap { $0.isEmpty ? nil : $0 } ?? "Transfer")
                      .foregroundStyle(.primary)
                    Text(entry.date, style: .date)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(BudgetMoney.formatted(entry.amountMinor, currencyCode: currencyCode))
                    .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(payeeNames[entry.id] ?? "Transfer"), \(BudgetMoney.formatted(entry.amountMinor, currencyCode: currencyCode)), \(selectedIDs.contains(entry.id) ? "cleared" : "uncleared")")
            }
            if visibleEntryCount < entries.count {
              Button("Show More Transactions") { visibleEntryCount += 300 }
            }
          }
        } header: {
          HStack {
            Text("Transactions")
            Spacer()
            Button("Select All") {
              selectedIDs = Set(entries.map(\.id))
              clearedBalanceMinor = calculator.clearedBalance(
                openingBalanceMinor: account.openingBalanceMinor,
                entries: entries, selectedIDs: selectedIDs
              )
            }
              .textCase(nil)
          }
        } footer: {
          Text("Select the transactions that cleared by your statement date. Reconciliation does not add or remove money.")
        }
      }
      .navigationTitle("Reconcile \(account.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Finish") { Task { await finish() } }
            .disabled(difference != 0 || isFinishing)
        }
      }
      .task(id: statementDate) {
        await loadEntries()
      }
      .alert("Couldn’t Reconcile", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func finish() async {
    guard let enteredBalance, enteredBalance == clearedBalanceMinor else { return }
    guard !isFinishing else { return }
    isFinishing = true
    defer { isFinishing = false }
    do {
      try await ReconciliationRepository(modelContainer: modelContext.container).finish(
        accountID: account.id, through: statementDate,
        balanceMinor: enteredBalance, selectedIDs: selectedIDs
      )
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private func loadEntries() async {
    let accountID = account.id
    let requestedDate = statementDate
    do {
      let result = try await ReconciliationRepository(modelContainer: modelContext.container)
        .load(accountID: accountID, through: requestedDate)
      guard requestedDate == statementDate, !Task.isCancelled else { return }
      entries = result.entries
      payeeNames = result.payeeNames
      visibleEntryCount = 300
      selectedIDs = Set(result.entries.filter(\.isCleared).map(\.id))
      clearedBalanceMinor = calculator.clearedBalance(
        openingBalanceMinor: account.openingBalanceMinor,
        entries: result.entries, selectedIDs: selectedIDs
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
