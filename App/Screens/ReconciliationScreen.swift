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
  @State private var hasLoaded = false
  @AppStorage(BowIntroKey.reconcile) private var hasSeenIntro = false
  @Environment(\.bowToasts) private var toasts

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
      Group {
        if hasSeenIntro {
          reconcileList
        } else {
          List {
            BowFeatureIntro(
              systemImage: "checkmark.seal",
              title: "Check Bow against your statement",
              points: [
                .init(systemImage: "doc.text", text: "Enter the balance your bank statement shows."),
                .init(systemImage: "checkmark.circle", text: "Tick off the transactions that cleared."),
                .init(systemImage: "equal.circle", text: "When it’s $0 off, you’re done. Nothing moves money.")
              ],
              actionTitle: "Start"
            ) {
              hasSeenIntro = true
            }
            .listRowBackground(Color.clear)
          }
          .bowSkyList(mood: .reconcile, height: 420)
          .navigationTitle("Reconcile")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          }
        }
      }
      .bowAnimation(value: hasSeenIntro)
    }
  }

  private var reconcileList: some View {
      List {
        Section {
          VStack(spacing: Bow.Space.s1) {
            CurrencyAmountField("Statement balance", minor: $statementBalanceMinor,
                                currencyCode: currencyCode, allowsNegative: true, style: .editorHero,
                                focusOnAppear: statementBalanceMinor == 0)
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
          if !hasLoaded {
            BowTransactionSkeletonRows(count: 3)
          } else if entries.isEmpty {
            ContentUnavailableView(
              "Nothing to reconcile before \(statementDate.formatted(.dateTime.month(.abbreviated).day()))",
              systemImage: "list.bullet.rectangle",
              description: Text("Try a later statement date.")
            )
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
                HStack(spacing: Bow.Space.s3) {
                  Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(entry.id) ? Bow.bowSolid : Bow.inkFaint)
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
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
                            showsPlusSign: entry.amountMinor > 0)
                    .foregroundStyle(Bow.ink)
                }
                .contentShape(Rectangle())
              }
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
      .bowEditorSheet(hasChanges: statementBalanceMinor != 0)
      .bowAnimation(value: hasLoaded)
      .bowAnimation(value: selectedIDs)
      .sensoryFeedback(.selection, trigger: selectedIDs)
      .sensoryFeedback(.success, trigger: isBalanced) { wasBalanced, balanced in
        !wasBalanced && balanced && statementBalanceMinor != 0
      }
      .navigationTitle("Reconcile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: statementBalanceMinor != 0) { dismiss() }
      }
      .safeAreaInset(edge: .bottom) {
        BowBottomAction(isBalanced ? "Finish reconciling" : "Off by \(BudgetMoney.formatted(abs(difference ?? 0), currencyCode: currencyCode))",
                        isEnabled: difference == 0 && !isFinishing) {
          Task { await finish() }
        }
      }
      .task(id: statementDate) {
        await loadEntries()
      }
      .bowErrorAlert("Couldn’t reconcile", message: $errorMessage)
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
      toasts?.show(.saved("\(account.name) reconciled · \(BudgetMoney.formatted(enteredBalance, currencyCode: currencyCode))"))
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
      hasLoaded = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
