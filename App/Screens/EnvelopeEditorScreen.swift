import SwiftUI
import SwiftData

/// The one envelope editor: new envelopes, envelope ideas, editing, and the target sheet.
struct EnvelopeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  var envelope: BudgetEnvelope?
  var layout: Layout = .envelope
  /// An envelope idea fills in the name, and its group if you already have one by that name.
  var idea: EnvelopeIdea?
  var onAdded: (() -> Void)?

  enum Layout {
    /// Name first: the envelope's name, group and target.
    case envelope
    /// Opened from the envelope's target tile: just the target.
    case target
  }
  @Query private var allGroups: [BudgetGroup]
  @Query private var profiles: [BudgetProfile]
  @Query private var schedules: [BudgetSchedule]
  @State private var name = ""
  @State private var groupID: UUID?
  @State private var targetAmountMinor: Int64 = 0
  @State private var targetKind: TargetPlanKind = .monthly
  @State private var targetDate = Date()
  @State private var errorMessage: String?
  @State private var initialFields: EnvelopeEditorFields?
  @State private var showingNewGroup = false
  @State private var carriedInMinor: Int64 = 0
  @State private var averageSpendingMinor: Int64?
  @FocusState private var nameIsFocused: Bool
  @State private var didRequestNameFocus = false

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  /// Regular groups in Budget order; card payments' group isn't a choice.
  private var groups: [BudgetGroup] {
    allGroups.filter { !$0.isSystem }
      .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  /// What scheduled bills add to this month's target.
  private var scheduledMinor: Int64 {
    guard let envelope else { return 0 }
    return ScheduleTargetCalculator().contributions(for: envelope.id, schedules: schedules, month: Date())
      .reduce(0) { $0 + $1.totalMinor }
  }

  /// Spending the scheduled bills don't already cover, so accepting it doesn't double count them.
  private var suggestedMinor: Int64? {
    guard let averageSpendingMinor else { return nil }
    let remainder = averageSpendingMinor - scheduledMinor
    return remainder > 0 ? remainder : nil
  }

  private var fields: EnvelopeEditorFields {
    EnvelopeEditorFields(name: name, groupID: groupID, target: targetAmountMinor,
                         targetDate: targetKind == .byDate ? targetDate : nil)
  }

  private var hasChanges: Bool { initialFields.map { fields != $0 } ?? false }

  private var isNew: Bool { envelope == nil }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && groupID != nil && (isNew || hasChanges)
  }

  init(groups: [BudgetGroup], envelope: BudgetEnvelope? = nil, layout: Layout = .envelope,
       idea: EnvelopeIdea? = nil, onAdded: (() -> Void)? = nil) {
    self.envelope = envelope
    self.layout = envelope == nil ? .envelope : layout
    self.idea = idea
    self.onAdded = onAdded
    _name = State(initialValue: envelope?.name ?? idea?.name ?? "")
    let initialGroup: UUID?
    if let envelope {
      initialGroup = envelope.groupID
    } else if let idea {
      // Only a group you already have; an idea never makes one up.
      initialGroup = groups.first {
        !$0.isSystem && $0.name.localizedCaseInsensitiveCompare(idea.groupName) == .orderedSame
      }?.id
    } else {
      initialGroup = nil
    }
    _groupID = State(initialValue: initialGroup)
    _targetAmountMinor = State(initialValue: envelope?.targetMinor ?? 0)
    _targetKind = State(initialValue: envelope?.targetDate == nil ? .monthly : .byDate)
    _targetDate = State(initialValue: envelope?.targetDate ?? Self.defaultTargetDate)
  }

  /// A year out: a sensible first guess for a savings goal.
  private static var defaultTargetDate: Date {
    Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
  }

  var body: some View {
    NavigationStack {
      Group {
        switch layout {
        case .envelope: envelopeForm
        case .target: targetSheet
        }
      }
      .bowSkyList(mood: .dawn, height: 420)
      .bowEditorSheet(hasChanges: hasChanges)
      .onAppear { if initialFields == nil { initialFields = fields } }
      .navigationBarTitleDisplayMode(.inline)
      .bowErrorAlert("Couldn’t save envelope", message: $errorMessage)
      .task { await loadTargetContext() }
    }
  }

  // MARK: - Envelope

  /// Name, group, and a Target row that opens the target editor.
  private var envelopeForm: some View {
    Form {
      Section {
        BowNameHeader(placeholder: "Envelope name", name: $name, isFocused: $nameIsFocused) {}
        .task {
          guard envelope == nil, idea == nil, !didRequestNameFocus else { return }
          await Task.yield()
          guard !Task.isCancelled else { return }
          didRequestNameFocus = true
          nameIsFocused = true
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
      Section {
        EnvelopeGroupMenu(selection: $groupID, groups: groups) { showingNewGroup = true }
        NavigationLink {
          EnvelopeTargetForm(
            amountMinor: $targetAmountMinor, kind: $targetKind, targetDate: $targetDate,
            currencyCode: currencyCode, scheduledMinor: scheduledMinor, carriedInMinor: carriedInMinor,
            suggestedMinor: suggestedMinor, focusOnAppear: targetAmountMinor == 0,
            onRemove: targetAmountMinor > 0 ? { clearTarget() } : nil, dismissesOnRemove: true
          )
          .bowSkyList(mood: .dawn, height: 420)
          .navigationTitle("Target")
          .navigationBarTitleDisplayMode(.inline)
        } label: {
          BowTileValueRow("Target", systemImage: "dollarsign", value: targetSummary)
        }
      } footer: {
        Text("Optional. A target is what to set aside each month; it never moves money by itself.")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)
    }
    .navigationTitle(isNew ? (idea == nil ? "New envelope" : "Add envelope") : "Envelope")
    .toolbar {
      BowCancelButton(hasChanges: hasChanges) { dismiss() }
      ToolbarItem(placement: .confirmationAction) {
        Button { save() } label: { BowToolbarLabel(isNew ? "Add" : "Save") }
          .disabled(!canSave)
      }
    }
    .sheet(isPresented: $showingNewGroup) {
      GroupEditorScreen(nextOrder: (groups.map(\.sortOrder).max() ?? -1) + 1) { group in
        groupID = group.id
      }
    }
  }

  /// "None", "$300 a month" or "$2,000 by Dec 2027".
  private var targetSummary: String {
    guard targetAmountMinor > 0 else { return "None" }
    let amount = BudgetMoney.formatted(targetAmountMinor, currencyCode: currencyCode)
    switch targetKind {
    case .monthly: return "\(amount) a month"
    case .byDate: return "\(amount) by \(targetDate.formatted(.dateTime.month(.abbreviated).year()))"
    }
  }

  // MARK: - Target sheet

  private var targetSheet: some View {
    EnvelopeTargetForm(
      amountMinor: $targetAmountMinor, kind: $targetKind, targetDate: $targetDate,
      currencyCode: currencyCode, scheduledMinor: scheduledMinor, carriedInMinor: carriedInMinor,
      suggestedMinor: suggestedMinor, focusOnAppear: (envelope?.targetMinor ?? 0) == 0,
      onRemove: (envelope?.targetMinor ?? 0) > 0 ? { removeTarget() } : nil
    )
    .navigationTitle("Target")
    .navigationSubtitle(name)
    .toolbar {
      BowCancelButton(hasChanges: hasChanges) { dismiss() }
    }
    // A money sheet: one primary action at the bottom, like the other money editors.
    .safeAreaInset(edge: .bottom) {
      BowBottomAction("Save target", isEnabled: canSave) { save() }
    }
  }

  // MARK: - Actions

  /// This month's carried-in balance, which a goal counts toward, and recent spending for the suggestion.
  private func loadTargetContext() async {
    guard let envelope else { return }
    let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
    if let snapshot = try? await repository.snapshot(month: Date()) {
      carriedInMinor = snapshot.carriedIn(for: envelope.id)
    }
    let calendar = Calendar.current
    let month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: month) ?? .distantPast
    let envelopeID = envelope.id
    let predicate = #Predicate<BudgetTransaction> {
      $0.envelopeID == envelopeID && $0.date >= sixMonthsAgo && $0.date < month
    }
    let recent = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    averageSpendingMinor = EnvelopeFundingAdvisor().suggestedMonthlyMinor(envelopeID: envelopeID, transactions: recent)
  }

  private func clearTarget() {
    targetAmountMinor = 0
    targetKind = .monthly
    targetDate = Self.defaultTargetDate
  }

  private func removeTarget() {
    clearTarget()
    save()
  }

  private func save() {
    guard let groupID else { return }
    guard groups.contains(where: { $0.id == groupID }) else {
      errorMessage = "Choose a regular envelope group."
      return
    }
    let targetMinor = targetAmountMinor > 0 ? targetAmountMinor : nil
    let savedDate = targetMinor != nil && targetKind == .byDate ? targetDate : nil
    do {
      if let envelope {
        if envelope.groupID != groupID {
          envelope.sortOrder = try BudgetCommands.nextEnvelopeOrder(in: groupID, context: modelContext)
        }
        envelope.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        envelope.groupID = groupID
        envelope.targetMinor = targetMinor
        envelope.targetDate = savedDate
        try modelContext.save()
        if layout == .target {
          toasts?.show(.saved(targetMinor == nil ? "Target removed" : "Target saved"))
        }
      } else {
        try BudgetCommands.addEnvelope(
          name: name,
          symbol: "",
          groupID: groupID,
          targetMinor: targetMinor,
          targetDate: savedDate,
          in: modelContext
        )
        toasts?.show(.saved("Added · \(name.trimmingCharacters(in: .whitespacesAndNewlines))"))
        onAdded?()
      }
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }
}

/// A suggested envelope from Envelope ideas.
struct EnvelopeIdea: Identifiable, Hashable {
  var name: String
  var groupName: String
  var id: String { groupName + "/" + name }
}

private struct EnvelopeEditorFields: Equatable {
  var name: String
  var groupID: UUID?
  var target: Int64
  var targetDate: Date?
}
