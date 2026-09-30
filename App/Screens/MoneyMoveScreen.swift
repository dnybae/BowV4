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
            PulseTarget(size: 150) {
              Image("BowMark")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .foregroundStyle(Bow.bow)
            }
            .accessibilityHidden(true)

            VStack(spacing: Bow.Space.s1) {
              Text("Amount")
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
              CurrencyAmountField("Amount to move", minor: $amountMinor, currencyCode: currencyCode, style: .hero)
              if let enteredMinor, enteredMinor > sourceAvailable {
                Text("Only \(BudgetMoney.formatted(max(0, sourceAvailable), currencyCode: currencyCode)) is available to move.")
                  .font(.bowFootnote)
                  .foregroundStyle(Bow.overInk)
              }
            }

            Button("Move all") {
              amountMinor = max(0, sourceAvailable)
            }
            .bowSecondaryButton()
            .disabled(sourceAvailable <= 0)

            Text("Recorded in \(month.formatted(.dateTime.month(.wide).year())). Remaining balances carry into later months.")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: Bow.Space.s4, bottom: Bow.Space.s2, trailing: Bow.Space.s4))

        if let snapshot { Section {
          BudgetBucketSelectionField(
            title: "From", selection: $source,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          BudgetBucketSelectionField(
            title: "To", selection: $target,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          Button("Swap direction", systemImage: "arrow.up.arrow.down") {
            let oldSource = source
            source = target
            target = oldSource
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
        }
        .listRowBackground(Bow.card)
      }
      .bowListBackground {
        Bow.mist.overlay(alignment: .top) { SkyBackground(mood: .dawn, height: 460) }
      }
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
      Image(systemName: bucketSymbol(bucket))
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Bow.bowInk)
        .frame(width: 36, height: 36)
        .background(Bow.bowTint, in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(role)
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
        Text(bucketName(bucket))
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
      }
      Spacer(minLength: Bow.Space.s2)
      VStack(alignment: .trailing, spacing: 1) {
        if changes {
          Text(beforeText)
            .font(.bowFootnote)
            .monospacedDigit()
            .strikethrough()
            .foregroundStyle(Bow.inkSoft)
        }
        Text(afterText)
          .font(.bowAmount)
          .monospacedDigit()
          .foregroundStyle(after < 0 ? Bow.overInk : Bow.ink)
      }
    }
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(role) \(bucketName(bucket))")
    .accessibilityValue(changes ? "\(beforeText) now, \(afterText) after moving" : afterText)
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
    let now = Date()
    let monthInterval = Calendar.current.dateInterval(of: .month, for: month)
    let allocationDate: Date
    if Calendar.current.isDate(month, equalTo: now, toGranularity: .month) {
      allocationDate = now
    } else if month < now {
      allocationDate = monthInterval?.end.addingTimeInterval(-1) ?? month
    } else {
      allocationDate = monthInterval?.start ?? month
    }
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
