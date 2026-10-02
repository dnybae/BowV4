import SwiftUI
import SwiftData

/// Covers one overspent envelope from one or more donors. Each donor has a slider and a typed
/// amount; nothing is saved until Cover is tapped, and then every donor is saved together.
struct CoverEnvelopeScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var schedules: [BudgetSchedule]
  var envelopeID: UUID
  var currencyCode: String
  var month: Date
  var snapshot: BudgetSnapshot
  var envelopes: [BudgetEnvelope]
  var groups: [BudgetGroup]
  var onCancel: () -> Void
  var onCovered: () -> Void
  @State private var draft: OverspendingCoverDraft
  @State private var showingDonorPicker = false
  @State private var errorMessage: String?
  @State private var isSaving = false
  @State private var didOfferDonors = false
  @Environment(\.bowToasts) private var toasts
  @ScaledMetric(relativeTo: .body) private var amountFieldWidth: CGFloat = 104

  init(
    envelopeID: UUID, currencyCode: String, month: Date, snapshot: BudgetSnapshot,
    envelopes: [BudgetEnvelope], groups: [BudgetGroup],
    onCancel: @escaping () -> Void, onCovered: @escaping () -> Void
  ) {
    self.envelopeID = envelopeID
    self.currencyCode = currencyCode
    self.month = month
    self.snapshot = snapshot
    self.envelopes = envelopes
    self.groups = groups
    self.onCancel = onCancel
    self.onCovered = onCovered
    _draft = State(initialValue: OverspendingCoverDraft(envelopeID: envelopeID))
  }

  private var envelope: BudgetEnvelope? { envelopes.first { $0.id == envelopeID } }
  private var remaining: Int64 { draft.remainingMinor(in: snapshot) }
  private var isCovered: Bool { remaining == 0 && draft.coveredMinor > 0 }

  private var scheduledTargets: [UUID: Int64] {
    ScheduleTargetCalculator().totalsByEnvelope(schedules: schedules, month: snapshot.month)
  }

  var body: some View {
    List {
      Section {
        BowIdentityHeader(
          name: envelope?.name ?? "Envelope",
          context: groups.first { $0.id == envelope?.groupID }?.name,
          amountMinor: snapshot.available(for: envelopeID),
          currencyCode: currencyCode,
          amountColor: Bow.overInk,
          pill: remaining > 0
            ? StatusPill(text: "\(BudgetMoney.formatted(remaining, currencyCode: currencyCode)) still to cover", state: .over)
            : StatusPill(text: "Fully covered", state: .funded, symbol: "checkmark")
        ) {
          BowGlossyTile(systemImage: TransactionIconSymbol.name(
            for: .expense, payee: "", envelope: envelope?.name
          ))
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      Section {
        ForEach(draft.donors) { donor in
          donorRow(donor)
        }
        Button {
          showingDonorPicker = true
        } label: {
          HStack {
            Label(draft.donors.isEmpty ? "Choose an envelope to cover from" : "Select another",
                  systemImage: "plus")
              .labelStyle(.bowTile)
            Spacer(minLength: Bow.Space.s2)
            Image(systemName: "chevron.right")
              .font(.bowFootnote.weight(.semibold))
              .foregroundStyle(Bow.inkFaint)
              .accessibilityHidden(true)
          }
          .contentShape(.rect)
        }
        .disabled(remaining == 0)
      } header: {
        Text("Cover from")
      }
      .listRowBackground(Bow.card)
    }
    .disabled(isSaving)
    .bowSkyList(mood: isCovered ? .mint : .coral, height: 420)
    .bowAnimation(value: remaining)
    .bowAnimation(value: draft.donors.map(\.bucket))
    .bowEditorSheet(hasChanges: !draft.donors.isEmpty)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      BowCancelButton(hasChanges: !draft.donors.isEmpty, onCancel: onCancel)
    }
    .navigationTitle("Cover overspending")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      BowBottomAction(isEnabled: draft.canSave(in: snapshot) && !isSaving, action: { Task { await save() } }) {
        HStack(spacing: Bow.Space.s1) {
          Text("Cover")
          MoneyText(minor: draft.coveredMinor, currencyCode: currencyCode)
        }
      }
    }
    .sensoryFeedback(.success, trigger: isCovered) { _, covered in covered }
    .onChange(of: snapshot.month) { _, _ in draft.clamp(to: snapshot) }
    .onChange(of: snapshot.available(for: envelopeID)) { _, _ in draft.clamp(to: snapshot) }
    .onAppear {
      guard !didOfferDonors else { return }
      didOfferDonors = true
      if draft.donors.isEmpty { showingDonorPicker = true }
    }
    .navigationDestination(isPresented: $showingDonorPicker) {
      CoverDonorPickerScreen(
        excluded: Set(draft.donors.map(\.bucket)).union([.envelope(envelopeID)]),
        currencyCode: currencyCode, snapshot: snapshot, envelopes: envelopes, groups: groups
      ) { bucket in
        draft.add(bucket, in: snapshot)
        showingDonorPicker = false
      }
    }
    .bowErrorAlert("Couldn’t Cover Overspending", message: $errorMessage)
  }

  private func donorRow(_ donor: OverspendingCoverDraft.Donor) -> some View {
    let name = donorName(donor.bucket)
    let available = draft.availableMinor(of: donor.bucket, in: snapshot)
    let maximum = draft.maximumMinor(for: donor.bucket, in: snapshot)
    let amount = Binding<Int64>(
      get: { draft.amountMinor(for: donor.bucket) },
      set: { draft.setAmount($0, for: donor.bucket, in: snapshot) }
    )
    let leftover = available - donor.amountMinor
    // A tick every tenth of the way along the slider, not on every cent.
    let sliderStep = maximum > 0 ? Int((Double(donor.amountMinor) / Double(maximum) * 10).rounded()) : 0
    return VStack(alignment: .leading, spacing: Bow.Space.s2) {
      HStack(spacing: Bow.Space.s3) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(name)
              .foregroundStyle(Bow.ink)
              .lineLimit(1)
            HStack(spacing: Bow.Space.s1) {
              MoneyText(minor: leftover, currencyCode: currencyCode)
              Text("left")
            }
            .font(.bowSubhead)
            .foregroundStyle(leftoverState(for: donor.bucket, leftover: leftover).ink)
          }
        } icon: {
          Image(systemName: donorSymbol(donor.bucket))
        }
        .labelStyle(.bowTile)
        .accessibilityElement(children: .combine)
        Spacer(minLength: Bow.Space.s2)
        CurrencyAmountField("Amount from \(name)", minor: amount, currencyCode: currencyCode)
          .labelsHidden()
          .frame(width: amountFieldWidth)
        Button("Remove \(name)", systemImage: "minus.circle.fill", role: .destructive) {
          withAnimation(Bow.motion(reduceMotion: reduceMotion)) { draft.remove(donor.bucket) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(Bow.inkFaint)
      }
      Slider(
        value: Binding(
          get: { Double(amount.wrappedValue) },
          set: { amount.wrappedValue = Int64($0.rounded()) }
        ),
        in: 0...Double(max(1, maximum))
      ) {
        Text("Amount from \(name)")
      }
      .disabled(maximum == 0)
      .sensoryFeedback(.selection, trigger: sliderStep)
      .accessibilityValue(BudgetMoney.formatted(amount.wrappedValue, currencyCode: currencyCode))
    }
    .padding(.vertical, Bow.Space.s1)
  }

  /// Amber once the donor drops below what its target needs this month, otherwise its usual color.
  private func leftoverState(for bucket: BudgetBucket, leftover: Int64) -> EnvelopeState {
    guard case .envelope(let id) = bucket, let donor = envelopes.first(where: { $0.id == id }) else {
      return leftover > 0 ? .funded : .empty
    }
    let target = (donor.targetMinor ?? 0) + scheduledTargets[id, default: 0]
    let assignedAfter = snapshot.assigned[id, default: 0] - draft.amountMinor(for: bucket)
    if target > 0 && assignedAfter < target { return .needs }
    return leftover > 0 ? .funded : .empty
  }

  private func donorSymbol(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "square.grid.2x2"
    case .envelope(let id):
      TransactionIconSymbol.name(for: .expense, payee: "", envelope: envelopes.first { $0.id == id }?.name)
    case .cardPayment: "creditcard"
    }
  }

  private func donorName(_ bucket: BudgetBucket) -> String {
    switch bucket {
    case .readyToAssign: "Ready to Assign"
    case .envelope(let id): envelopes.first { $0.id == id }?.name ?? "Envelope"
    case .cardPayment: "Card Payment"
    }
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      await repository.invalidate()
      let current = try await repository.snapshot(month: month)
      try BudgetCommands.coverOverspending(
        envelopeID: envelopeID, from: draft.donorAmounts,
        date: BudgetCommands.allocationDate(inMonth: month),
        snapshot: current, in: modelContext
      )
      toasts?.show(.moved("Covered \(envelope?.name ?? "envelope") · \(BudgetMoney.formatted(draft.coveredMinor, currencyCode: currencyCode))"))
      onCovered()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
