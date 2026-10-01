import SwiftUI
import SwiftData

struct MoneyMoveScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Query private var currentAccounts: [BudgetAccount]
  @Query private var currentEnvelopes: [BudgetEnvelope]
  var currencyCode: String
  var month: Date
  @State private var source: BudgetBucket
  @State private var target: BudgetBucket
  @State private var amountMinor: Int64 = 0
  @State private var errorMessage: String?
  @State private var snapshot: BudgetSnapshot?
  @State private var refreshVersion = 0

  init(
    currencyCode: String,
    month: Date,
    source: BudgetBucket,
    target: BudgetBucket
  ) {
    self.currencyCode = currencyCode
    self.month = month
    _source = State(initialValue: source)
    _target = State(initialValue: target)
  }

  private var cardAccounts: [BudgetAccount] {
    currentAccounts.filter { $0.kind == .credit }.sorted { $0.name < $1.name }
  }

  private var sourceAvailable: Int64 { balance(of: source) }
  private var enteredMinor: Int64? { amountMinor }
  private var isValid: Bool {
    snapshot != nil && source != target && (enteredMinor ?? 0) > 0
      && (enteredMinor ?? 0) <= max(0, sourceAvailable)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: Bow.Space.s3) {
            CurrencyAmountField("Amount", minor: $amountMinor, currencyCode: currencyCode, style: .editorHero)
            if let enteredMinor, enteredMinor > sourceAvailable {
              Text("Only \(BudgetMoney.formatted(max(0, sourceAvailable), currencyCode: currencyCode)) is available to move.")
                .font(.bowFootnote)
                .foregroundStyle(Bow.overInk)
            }
            Button("Move all") {
              amountMinor = max(0, sourceAvailable)
            }
            .fontWeight(.semibold)
            .bowSecondaryButton(size: .regular)
            .disabled(sourceAvailable <= 0)
          }
          .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: Bow.Space.s4, bottom: Bow.Space.s2, trailing: Bow.Space.s4))

        if let snapshot { Section {
          BudgetBucketSelectionField(
            title: "From", selection: $source,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode, systemImage: bucketSymbol(source)
          )
          BudgetBucketSelectionField(
            title: "To", selection: $target,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode, systemImage: bucketSymbol(target)
          )
          Button {
            let oldSource = source
            source = target
            target = oldSource
          } label: {
            Label("Swap direction", systemImage: "arrow.up.arrow.down").labelStyle(.bowTile)
          }
          .disabled(source == target)
        } header: {
          Text("Move between")
        }
        .listRowBackground(Bow.card)
        } else {
          Section { ProgressView("Calculating balances…") }
          .listRowBackground(Bow.card)
        }

        Section {
          balanceRow("From", bucket: source, before: sourceAvailable, after: sourceAvailable - (enteredMinor ?? 0))
          balanceRow("To", bucket: target, before: balance(of: target), after: balance(of: target) + (enteredMinor ?? 0))
        } header: {
          Text("After moving")
        } footer: {
          Text("Recorded in \(month.formatted(.dateTime.month(.wide).year())). Remaining balances carry into later months.")
        }
        .listRowBackground(Bow.card)
      }
      .bowSkyList(mood: .dawn, height: 420)
      .navigationTitle("Move money")
      .task(id: refreshVersion) {
        let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
        snapshot = try? await repository.snapshot(month: month)
      }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        refreshVersion += 1
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button { Task { await save() } } label: {
          Text("Move \(BudgetMoney.formatted(enteredMinor ?? 0, currencyCode: currencyCode))")
            .fontWeight(.semibold)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .bowPrimaryButton()
        .disabled(!isValid)
        .padding(.horizontal, Bow.Space.s4)
        .padding(.bottom, Bow.Space.s2)
      }
      .alert("Couldn’t Move Money", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func balance(of bucket: BudgetBucket) -> Int64 {
    guard let snapshot else { return 0 }
    switch bucket {
    case .readyToAssign: return snapshot.readyToAssignMinor
    case .envelope(let id): return snapshot.available(for: id)
    case .cardPayment(let id): return snapshot.paymentAvailable[id, default: 0]
    }
  }

  private func balanceRow(_ role: String, bucket: BudgetBucket, before: Int64, after: Int64) -> some View {
    let changes = before != after
    let beforeText = BudgetMoney.formatted(before, currencyCode: currencyCode)
    let afterText = BudgetMoney.formatted(after, currencyCode: currencyCode)
    return HStack(spacing: Bow.Space.s3) {
      Text(bucketName(bucket))
        .foregroundStyle(Bow.ink)
      Spacer(minLength: Bow.Space.s2)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Bow.Space.s2) { amounts(changes: changes, before: beforeText, after: afterText, isNegative: after < 0) }
        VStack(alignment: .trailing, spacing: 1) { amounts(changes: changes, before: beforeText, after: afterText, isNegative: after < 0) }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(role) \(bucketName(bucket))")
    .accessibilityValue(changes ? "\(beforeText) now, \(afterText) after moving" : afterText)
  }

  /// The balance before (struck through, only when it changes) and after moving.
  @ViewBuilder
  private func amounts(changes: Bool, before: String, after: String, isNegative: Bool) -> some View {
    if changes {
      Text(before)
        .strikethrough()
        .foregroundStyle(Bow.inkSoft)
    }
    Text(after)
      .foregroundStyle(isNegative ? Bow.overInk : Bow.ink)
  }

  private func bucketSymbol(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "square.grid.2x2"
    case .envelope(let id): currentEnvelopes.first { $0.id == id }?.symbol ?? "tray"
    case .cardPayment: "creditcard"
    }
  }

  private func bucketName(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): currentEnvelopes.first { $0.id == id }?.name ?? "Envelope"
    case .cardPayment(let id): (currentAccounts.first { $0.id == id }?.name ?? "Card") + " Payment"
    }
  }

  private func save() async {
    guard let minor = enteredMinor, minor > 0 else {
      errorMessage = "Enter an amount greater than zero."
      return
    }
    guard source != target else {
      errorMessage = "Choose two different places for the money."
      return
    }
    let validEnvelopeIDs = Set(currentEnvelopes.map(\.id))
    let validCardIDs = Set(cardAccounts.map(\.id))
    for bucket in [source, target] {
      switch bucket {
      case .readyToAssign: break
      case .envelope(let id):
        guard validEnvelopeIDs.contains(id) else {
          errorMessage = "An envelope changed. Choose it again."
          return
        }
      case .cardPayment(let id):
        guard validCardIDs.contains(id) else {
          errorMessage = "A card changed. Choose it again."
          return
        }
      }
    }
    let allocationDate = BudgetCommands.allocationDate(inMonth: month)
    do {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      await repository.invalidate()
      let current = try await repository.snapshot(month: month)
      snapshot = current
      try BudgetCommands.moveMoney(
        amountMinor: minor, from: source, to: target,
        date: allocationDate, snapshot: current, in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
