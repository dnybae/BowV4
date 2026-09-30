import SwiftUI
import SwiftData

/// Lists every overspent envelope in a month, each on its own card. Choosing one opens
/// `CoverEnvelopeScreen` to pick donors. Closes itself once nothing is left overspent.
struct CoverOverspendingScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var groups: [BudgetGroup]
  @Query private var accounts: [BudgetAccount]
  var currencyCode: String
  var month: Date
  /// When set, only envelopes overspent on this card are listed.
  var cardID: UUID?
  @State private var snapshot: BudgetSnapshot?
  @State private var refreshVersion = 0
  @State private var path: [UUID] = []
  @State private var coveredCount = 0

  private var isPastMonth: Bool {
    (Calendar.current.dateInterval(of: .month, for: month)?.start ?? month)
      < (Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date())
  }

  private var overspending: OverspendingSummary? {
    snapshot.map { OverspendingSummary(snapshot: $0, envelopes: envelopes, groups: groups, cardID: cardID) }
  }

  private var cardName: String? {
    cardID.flatMap { id in accounts.first { $0.id == id }?.name }
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if let snapshot, let overspending {
          header(overspending)
          ForEach(overspending.items) { item in
            if let envelope = envelopes.first(where: { $0.id == item.envelopeID }) {
              Section {
                row(for: envelope, item: item, snapshot: snapshot)
              }
              .listRowBackground(Bow.card)
              .listSectionSpacing(Bow.Space.s3)
            }
          }
        } else {
          ProgressView("Calculating balances…")
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
      }
      .bowListBackground {
        Bow.mist.overlay(alignment: .top) {
          SkyBackground(mood: overspending?.isEmpty == false ? .coral : .mint, height: 460)
        }
      }
      .animation(reduceMotion ? nil : .snappy, value: overspending?.items.map(\.envelopeID))
      .navigationTitle("Cover overspending")
      .navigationSubtitle(cardName.map { "Spent on \($0)" } ?? "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { dismiss() }
        }
      }
      .navigationDestination(for: UUID.self) { envelopeID in
        if let snapshot {
          CoverEnvelopeScreen(
            envelopeID: envelopeID, currencyCode: currencyCode, month: month,
            snapshot: snapshot, envelopes: envelopes, groups: groups
          ) {
            coveredCount += 1
            path.removeAll()
          }
        }
      }
      .task(id: refreshVersion) {
        let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
        await repository.invalidate()
        snapshot = try? await repository.snapshot(month: month)
      }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
        refreshVersion += 1
      }
      .onChange(of: overspending?.isEmpty) { _, isEmpty in
        guard isEmpty == true, coveredCount > 0 else { return }
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(700))
          dismiss()
        }
      }
      .sensoryFeedback(.success, trigger: coveredCount)
    }
  }

  @ViewBuilder
  private func header(_ overspending: OverspendingSummary) -> some View {
    Section {
      VStack(spacing: Bow.Space.s1) {
        if overspending.isEmpty {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(Bow.funded)
            .accessibilityHidden(true)
          Text("Everything’s covered")
            .font(.bowTitle)
            .foregroundStyle(Bow.ink)
        } else {
          Text(BudgetMoney.formatted(overspending.totalMinor, currencyCode: currencyCode))
            .font(.bowHero)
            .monospacedDigit()
            .foregroundStyle(Bow.overInk)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
          Text(overspending.items.count == 1 ? "overspent in 1 envelope" : "overspent in \(overspending.items.count) envelopes")
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
          Text(isPastMonth ? "Past budget months are view only." : consequence(overspending))
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
            .multilineTextAlignment(.center)
            .padding(.top, Bow.Space.s2)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Bow.Space.s4)
      .accessibilityElement(children: .combine)
    }
    .listRowBackground(Color.clear)
  }

  private func consequence(_ overspending: OverspendingSummary) -> String {
    switch (overspending.cashMinor > 0, overspending.creditMinor > 0) {
    case (true, true): "Choose an envelope to cover. Uncovered cash comes out of next month, and uncovered credit becomes card debt."
    case (false, true): "Choose an envelope to cover. Uncovered credit spending becomes card debt at the end of the month."
    default: "Choose an envelope to cover. Uncovered cash comes out of next month’s Ready to Assign."
    }
  }

  @ViewBuilder
  private func row(for envelope: BudgetEnvelope, item: OverspendingSummary.Item, snapshot: BudgetSnapshot) -> some View {
    let content = VStack(alignment: .leading, spacing: 2) {
      EnvelopeBudgetRow(
        name: envelope.name,
        availableMinor: snapshot.available(for: envelope.id),
        cashOverspentMinor: item.cashMinor,
        creditOverspentMinor: item.creditMinor,
        assignedMinor: snapshot.assigned[envelope.id, default: 0],
        activityMinor: snapshot.activity[envelope.id, default: 0],
        monthlyTargetMinor: nil,
        currencyCode: currencyCode
      )
      if envelope.isHidden {
        Text("Hidden")
          .font(.bowCaption)
          .foregroundStyle(Bow.inkSoft)
          .padding(.leading, 40)
      }
    }
    if isPastMonth {
      content
    } else {
      NavigationLink(value: envelope.id) { content }
        .accessibilityHint("Choose envelopes to cover this overspending")
    }
  }
}
