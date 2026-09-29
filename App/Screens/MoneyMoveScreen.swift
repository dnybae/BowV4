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
  @State private var amount = ""
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
  private var enteredMinor: Int64? { BudgetMoney.parseMinor(amount) }
  private var isValid: Bool {
    snapshot != nil && source != target && (enteredMinor ?? 0) > 0
      && (enteredMinor ?? 0) <= max(0, sourceAvailable)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 7) {
            Text(month.formatted(.dateTime.month(.wide).year()) + " Budget")
              .font(.title2.weight(.semibold))
              .foregroundStyle(.primary)
            Text("This move is recorded in this month. Remaining balances carry into later months.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
          .accessibilityElement(children: .combine)
        }

        if let snapshot { Section {
          BudgetBucketSelectionField(
            title: "From", selection: $source,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          LabeledContent("Available", value: BudgetMoney.formatted(sourceAvailable, currencyCode: currencyCode))
          BudgetBucketSelectionField(
            title: "To", selection: $target,
            envelopes: currentEnvelopes, cardAccounts: cardAccounts,
            snapshot: snapshot, currencyCode: currencyCode
          )
          Button("Swap Direction", systemImage: "arrow.up.arrow.down") {
            let oldSource = source
            source = target
            target = oldSource
          }
          .disabled(source == target)
        } header: {
          Text("Move Between")
        } footer: {
          Text("Choose the money’s current location and where it should go.")
        } } else {
          Section { ProgressView("Calculating balances…") }
        }

        Section("Amount") {
          HStack {
            TextField("0.00", text: $amount)
              .keyboardType(.decimalPad)
              .accessibilityLabel("Amount to move")
            Button("Move All") {
              amount = BudgetMoney.editable(max(0, sourceAvailable))
            }
            .disabled(sourceAvailable <= 0)
          }
          if let enteredMinor, enteredMinor > sourceAvailable {
            Text("Only \(BudgetMoney.formatted(max(0, sourceAvailable), currencyCode: currencyCode)) is available to move.")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        Section("After Moving") {
          LabeledContent(bucketName(source), value: BudgetMoney.formatted(
            sourceAvailable - (enteredMinor ?? 0), currencyCode: currencyCode
          ))
          LabeledContent(bucketName(target), value: BudgetMoney.formatted(
            balance(of: target) + (enteredMinor ?? 0), currencyCode: currencyCode
          ))
        }

      }
      .navigationTitle("Move Money")
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
        Button(action: save) {
          Text("Move \(BudgetMoney.formatted(enteredMinor ?? 0, currencyCode: currencyCode)) in \(month.formatted(.dateTime.month(.wide)))")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
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

  private func bucketName(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): currentEnvelopes.first { $0.id == id }?.name ?? "Envelope"
    case .cardPayment(let id): (currentAccounts.first { $0.id == id }?.name ?? "Card") + " Payment"
    }
  }

  private func save() {
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
      try BudgetCommands.moveMoney(
        amountMinor: minor, from: source, to: target,
        date: allocationDate, in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
