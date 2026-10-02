import SwiftUI
import SwiftData

/// Funds targets without asking people to pick an arbitrary first envelope.
struct AssignMoneyScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Environment(\.bowToasts) private var toasts
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var schedules: [BudgetSchedule]
  var month: Date
  var currencyCode: String
  var onCustomAmount: (UUID) -> Void
  @State private var snapshot: BudgetSnapshot?
  @State private var refreshVersion = 0
  @State private var isSaving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        if let snapshot {
          Section {
            LabeledContent("Ready to Assign") {
              MoneyText(minor: snapshot.readyToAssignMinor, currencyCode: currencyCode)
            }
          } footer: {
            Text("Assigning for \(month.formatted(.dateTime.month(.wide).year())). Fund a target in one tap, or choose a custom amount.")
          }
          .listRowBackground(Bow.card)
          let scheduled = ScheduleTargetCalculator().totalsByEnvelope(schedules: schedules, month: month)
          ForEach(groups.filter { !$0.isSystem }.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
          }) { group in
            let visible = envelopes.filter {
              $0.groupID == group.id && !$0.isHidden && $0.paymentAccountID == nil
            }.sorted { lhs, rhs in
              lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
            }
            if !visible.isEmpty {
              Section(group.name) {
                ForEach(visible) { envelope in
                  let remaining = remainingTarget(envelope, scheduled: scheduled, snapshot: snapshot)
                  VStack(alignment: .leading, spacing: Bow.Space.s2) {
                    Text(envelope.name).font(.bowHeadline)
                    if let remaining {
                      Text(remaining == 0 ? "Target funded" : "Needs \(BudgetMoney.formatted(remaining, currencyCode: currencyCode))")
                        .font(.bowSubhead).foregroundStyle(Bow.inkSoft)
                      if remaining > 0 {
                        Button("Fund Target · \(BudgetMoney.formatted(remaining, currencyCode: currencyCode))") {
                          Task { await fund(envelope.id) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSaving || remaining > snapshot.readyToAssignMinor)
                        .accessibilityLabel("Fund \(envelope.name) with \(BudgetMoney.formatted(remaining, currencyCode: currencyCode))")
                        if remaining > snapshot.readyToAssignMinor {
                          Text("Not enough ready to assign. Choose a smaller amount.")
                            .font(.bowFootnote).foregroundStyle(Bow.inkSoft)
                        }
                      }
                    } else {
                      Text("No target").font(.bowSubhead).foregroundStyle(Bow.inkSoft)
                    }
                    Button("Custom Amount…") { onCustomAmount(envelope.id) }
                      .buttonStyle(.borderless)
                      .accessibilityLabel("Assign a custom amount to \(envelope.name)")
                  }
                  .padding(.vertical, Bow.Space.s1)
                }
              }
              .listRowBackground(Bow.card)
            }
          }
        } else {
          BowLoadingLabel("Calculating balances…")
        }
      }
      .disabled(isSaving)
      .bowListBackground()
      .navigationTitle("Assign Money")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .task(id: refreshVersion) { await reload() }
      .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refreshVersion += 1 }
      .bowErrorAlert("Couldn’t Assign Money", message: $errorMessage)
    }
    .bowToastHost()
  }

  private func remainingTarget(_ envelope: BudgetEnvelope, scheduled: [UUID: Int64], snapshot: BudgetSnapshot) -> Int64? {
    EnvelopeTargetPlanner().monthlyMinor(for: envelope, scheduledMinor: scheduled[envelope.id, default: 0], snapshot: snapshot)
      .map { max(0, $0 - snapshot.assigned[envelope.id, default: 0]) }
  }

  private func reload() async {
    do {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      await repository.invalidate()
      snapshot = try await repository.snapshot(month: month)
    } catch { errorMessage = error.localizedDescription }
  }

  private func fund(_ id: UUID) async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      await repository.invalidate()
      let current = try await repository.snapshot(month: month)
      guard let envelope = envelopes.first(where: { $0.id == id && !$0.isHidden }) else { return }
      let scheduled = ScheduleTargetCalculator().totalsByEnvelope(schedules: schedules, month: month)
      guard let amount = remainingTarget(envelope, scheduled: scheduled, snapshot: current), amount > 0 else { return }
      let allocation = try BudgetCommands.moveMoney(
        amountMinor: amount, from: .readyToAssign, to: .envelope(id),
        date: BudgetCommands.allocationDate(inMonth: month), snapshot: current, in: modelContext
      )
      var toast = BowToast.moved("Funded \(envelope.name)")
      toast.undo = UndoableChanges.undoMove(allocation, in: modelContext)
      toasts?.show(toast)
      await repository.invalidate()
      snapshot = try await repository.snapshot(month: month)
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }
}
