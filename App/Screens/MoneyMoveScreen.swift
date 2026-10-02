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
  @State private var isSaving = false
  @State private var actionFeedback = 0
  @Environment(\.bowToasts) private var toasts
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    currentAccounts.filter { $0.kind == .credit && $0.closedAt == nil }.sorted { $0.name < $1.name }
  }

  private var sourceAvailable: Int64 { balance(of: source) }
  private var enteredMinor: Int64? { amountMinor }
  /// The amount typed is more than the source has.
  private var isOverAvailable: Bool { (enteredMinor ?? 0) > max(0, sourceAvailable) && snapshot != nil }

  private var isValid: Bool {
    snapshot != nil && source != target && (enteredMinor ?? 0) > 0
      && (enteredMinor ?? 0) <= max(0, sourceAvailable)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: Bow.Space.s3) {
            CurrencyAmountField("Amount", minor: $amountMinor, currencyCode: currencyCode, style: .editorHero,
                                focusOnAppear: true)
            if isOverAvailable {
              HStack(spacing: Bow.Space.s1) {
                Text("Only")
                MoneyText(minor: max(0, sourceAvailable), currencyCode: currencyCode)
                Text("is available to move.")
              }
              .font(.bowFootnote)
              .foregroundStyle(Bow.overInk)
              .accessibilityElement(children: .combine)
              .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Button("Move all") {
              amountMinor = max(0, sourceAvailable)
              actionFeedback += 1
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
            snapshot: snapshot, currencyCode: currencyCode, systemImage: "tray.and.arrow.up"
          )
          BudgetBucketSelectionField(
            title: "To", selection: $target,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode, systemImage: "tray.and.arrow.down"
          )
          Button {
            let oldSource = source
            source = target
            target = oldSource
            actionFeedback += 1
          } label: {
            Label("Swap direction", systemImage: "arrow.up.arrow.down").labelStyle(.bowTile)
          }
          .disabled(source == target)
        } header: {
          Text("Move between")
        }
        .listRowBackground(Bow.card)
        } else {
          Section {
            BowLoadingLabel("Calculating balances…")
              .frame(maxWidth: .infinity)
          }
          .listRowBackground(Bow.card)
        }

        Section {
          balanceRow("From", bucket: source, before: sourceAvailable, after: sourceAvailable - (enteredMinor ?? 0))
          balanceRow("To", bucket: target, before: balance(of: target), after: balance(of: target) + (enteredMinor ?? 0))
        } header: {
          Text("After moving")
        } footer: {
          Text("Recorded in \(month.formatted(.dateTime.month(.wide).year())). Remaining balances carry into later months.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
      }
      .disabled(isSaving)
      .bowSkyList(mood: .dawn, height: 420)
      .bowEditorSheet(hasChanges: amountMinor != 0)
      .bowAnimation(value: isOverAvailable)
      .sensoryFeedback(.impact(weight: .light), trigger: actionFeedback)
      .sensoryFeedback(.warning, trigger: isOverAvailable) { wasOver, isOver in !wasOver && isOver }
      .navigationTitle("Move money")
      .task(id: refreshVersion) {
        let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
        await repository.invalidate()
        snapshot = try? await repository.snapshot(month: month)
      }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        refreshVersion += 1
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: amountMinor != 0) { dismiss() }
      }
      .safeAreaInset(edge: .bottom) {
        BowBottomAction(isEnabled: isValid && !isSaving, action: { Task { await save() } }) {
          HStack(spacing: Bow.Space.s1) {
            Text("Move")
            MoneyText(minor: enteredMinor ?? 0, currencyCode: currencyCode)
          }
        }
      }
      .bowErrorAlert("Couldn’t Move Money", message: $errorMessage)
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
        HStack(spacing: Bow.Space.s2) { amounts(changes: changes, before: before, after: after) }
        VStack(alignment: .trailing, spacing: 1) { amounts(changes: changes, before: before, after: after) }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(role) \(bucketName(bucket))")
    .accessibilityValue(changes ? "\(beforeText) now, \(afterText) after moving" : afterText)
  }

  /// The balance before (struck through, only when it changes) and after moving, which rolls as you type.
  @ViewBuilder
  private func amounts(changes: Bool, before: Int64, after: Int64) -> some View {
    if changes {
      Text(BudgetMoney.formatted(before, currencyCode: currencyCode))
        .monospacedDigit()
        .strikethrough()
        .foregroundStyle(Bow.inkSoft)
    }
    MoneyText(minor: after, currencyCode: currencyCode)
      .foregroundStyle(after < 0 ? Bow.overInk : Bow.ink)
  }

  private func bucketName(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): currentEnvelopes.first { $0.id == id }?.name ?? "Envelope"
    case .cardPayment(let id): (currentAccounts.first { $0.id == id }?.name ?? "Card") + " Payment"
    }
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
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
      let allocation = try BudgetCommands.moveMoney(
        amountMinor: minor, from: source, to: target,
        date: allocationDate, snapshot: current, in: modelContext
      )
      var toast = BowToast.moved("Moved \(BudgetMoney.formatted(minor, currencyCode: currencyCode)) to \(bucketName(target))")
      toast.undo = UndoableChanges.undoMove(allocation, in: modelContext)
      toasts?.show(toast)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
