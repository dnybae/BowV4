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
  @State private var statementBalanceMinor: Int64 = 0
  @State private var selectedIDs: Set<UUID> = []
  @State private var visibleEntryCount = 300
  @State private var isFinishing = false
  @State private var errorMessage: String?

  private var calculator: ReconciliationCalculator { ReconciliationCalculator() }
  private var enteredBalance: Int64? { statementBalanceMinor }
  private var difference: Int64? { enteredBalance.map { $0 - clearedBalanceMinor } }

  /// Matches the rule the Finish button already uses: the statement equals the cleared balance.
  private var isBalanced: Bool { difference == 0 }

  private var heroTitle: String {
    if isBalanced { return "Balanced" }
    return "Off by \(BudgetMoney.formatted(abs(difference ?? 0), currencyCode: currencyCode))"
  }

  private var heroMessage: String {
    let statement = BudgetMoney.formatted(statementBalanceMinor, currencyCode: currencyCode)
    let date = statementDate.formatted(.dateTime.month(.abbreviated).day())
    if isBalanced {
      return "\(account.name) matches your bank statement of \(statement) on \(date)."
    }
    if statementBalanceMinor == 0 {
      return "Enter the balance on your statement, then check off what cleared."
    }
    return "Check off transactions that cleared by \(date) until the difference is zero."
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: Bow.Space.s1) {
            CurrencyAmountField("Statement balance", minor: $statementBalanceMinor,
                                currencyCode: currencyCode, allowsNegative: true, style: .editorHero)
            Text(account.name)
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
          }
          .padding(.bottom, Bow.Space.s2)
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }

        Section {
          NavigationLink {
            BowDatePickerScreen(title: "Statement date", date: $statementDate, range: Date.distantPast...Date())
          } label: {
            BowTileValueRow("Statement date", systemImage: "calendar",
                            value: statementDate.formatted(date: .abbreviated, time: .omitted))
          }
          BowTileValueRow(title: "Cleared balance", systemImage: "checkmark.circle") {
            MoneyText(minor: clearedBalanceMinor, currencyCode: currencyCode)
          }
          if let difference {
            BowTileValueRow(title: "Difference", systemImage: "dollarsign") {
              StatusPill(text: BudgetMoney.formatted(difference, currencyCode: currencyCode),
                         state: difference == 0 ? .funded : .needs)
            }
            .accessibilityElement(children: .combine)
          }
        } footer: {
          Text("\(isBalanced ? heroTitle + ". " : "")\(heroMessage)")
        }
        .listRowBackground(Bow.card)

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
                    .foregroundStyle(selectedIDs.contains(entry.id) ? Bow.bowSolid : Bow.inkFaint)
                    .font(.title2)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(payeeNames[entry.id].flatMap { $0.isEmpty ? nil : $0 } ?? "Transfer")
                      .font(.bowBody)
                      .foregroundStyle(Bow.ink)
                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                      .font(.bowFootnote)
                      .foregroundStyle(Bow.inkSoft)
                  }
                  Spacer()
                  MoneyText(minor: entry.amountMinor, currencyCode: currencyCode,
                            showsPlusSign: entry.amountMinor > 0, usesTrueMinus: true)
                    .monospacedDigit()
                    .foregroundStyle(Bow.ink)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(payeeNames[entry.id] ?? "Transfer"), \(BudgetMoney.formatted(entry.amountMinor, currencyCode: currencyCode)), \(selectedIDs.contains(entry.id) ? "cleared" : "uncleared")")
            }
            if visibleEntryCount < entries.count {
              Button("Show more transactions") { visibleEntryCount += 300 }
            }
            Button("Select all") {
              selectedIDs = Set(entries.map(\.id))
              clearedBalanceMinor = calculator.clearedBalance(
                openingBalanceMinor: account.openingBalanceMinor,
                entries: entries, selectedIDs: selectedIDs
              )
            }
            .disabled(selectedIDs.count == entries.count)
          }
        } header: {
          Text("Transactions")
        } footer: {
          Text("Select the transactions that cleared by your statement date. Reconciliation does not add or remove money.")
        }
        .listRowBackground(Bow.card)
      }
      .bowSkyList(mood: .reconcile, height: 420)
      .navigationTitle("Reconcile")
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
      .alert("Couldn’t reconcile", isPresented: Binding(
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
