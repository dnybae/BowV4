import SwiftUI
import SwiftData

struct EnvelopeManagementScreen: View {
  @Environment(\.bowToasts) private var toasts
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Query private var profiles: [BudgetProfile]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var accounts: [BudgetAccount]
  @State private var editor: EnvelopeGroupEditor?
  @State private var message: String?
  @State private var snapshot: BudgetSnapshot?
  @State private var refreshVersion = 0
  @State private var showingDirectory = false
  @State private var showingGroupOrder = false

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted {
      $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
    }
  }
  private var hiddenEnvelopes: [BudgetEnvelope] {
    envelopes.filter { $0.isHidden && $0.paymentAccountID == nil }.sorted { $0.name < $1.name }
  }

  private func activeEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter { $0.groupID == group.id && $0.paymentAccountID == nil && !$0.isHidden }
      .sorted { $0.sortOrder == $1.sortOrder
        ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    List {
      if groups.isEmpty {
        ContentUnavailableView(
          "No groups yet", systemImage: "folder",
          description: Text("Create a group to organize your envelopes.")
        )
      }

      ForEach(orderedGroups) { group in
        Section {
          ForEach(activeEnvelopes(in: group)) { envelope in
            envelopeRow(envelope)
          }
          .bowReorderable(collectionID: group.id)
          if activeEnvelopes(in: group).isEmpty {
            Text("No envelopes in this group")
              .foregroundStyle(Bow.inkSoft)
          }
        } header: {
          HStack {
            Text(group.name)
            Spacer()
            Button("Edit group") { editor = .editGroup(group) }
              .font(.bowSubhead.weight(.semibold))
              .accessibilityLabel("Edit \(group.name)")
          }
        }
        .listRowBackground(Bow.card)
      }

      if !hiddenEnvelopes.isEmpty {
        Section("Hidden envelopes") {
          ForEach(hiddenEnvelopes) { envelope in
            // Two buttons in one row: each keeps to its own area.
            HStack(spacing: Bow.Space.s3) {
              envelopeRow(envelope)
                .buttonStyle(.plain)
              Button("Unhide") { setHidden(envelope, false) }
                .buttonStyle(.borderless)
                .font(.bowSubhead.weight(.semibold))
                .accessibilityLabel("Unhide \(envelope.name)")
            }
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
    .bowEnvelopeReordering { moveEnvelopes($0, to: $1, before: $2) }
    .navigationTitle("Groups and envelopes")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("New Envelope", systemImage: "plus") { editor = .newEnvelope }
            .disabled(orderedGroups.isEmpty)
          Button("New Group", systemImage: "folder.badge.plus") { editor = .newGroup }
          Button("Browse Ideas", systemImage: "tray") { showingDirectory = true }
          Divider()
          Button("Reorder Groups") { showingGroupOrder = true }
            .disabled(orderedGroups.count < 2)
        } label: {
          Label("Manage Envelopes", systemImage: "plus").labelStyle(.iconOnly)
        }
      }
    }
    .sheet(isPresented: $showingGroupOrder) { GroupOrderScreen() }
    .navigationDestination(isPresented: $showingDirectory) { EnvelopeDirectoryScreen() }
    .task(id: refreshVersion) {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      snapshot = try? await repository.snapshot(month: Date())
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      refreshVersion += 1
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editor) { selection in
      switch selection {
      case .newGroup:
        GroupEditorScreen(nextOrder: groups.count)
      case .editGroup(let group):
        GroupEditorScreen(nextOrder: groups.count, group: group)
      case .newEnvelope:
        EnvelopeEditorScreen(groups: orderedGroups)
      case .editEnvelope(let envelope):
        EnvelopeEditorScreen(groups: orderedGroups, envelope: envelope)
      }
    }
    .bowErrorAlert("Envelope", message: $message)
  }

  private func envelopeRow(_ envelope: BudgetEnvelope) -> some View {
    Button {
      editor = .editEnvelope(envelope)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(envelope.name)
            .font(.bowHeadline)
            .foregroundStyle(Bow.ink)
          Text(targetSummary(envelope))
            .font(.bowFootnote)
            .foregroundStyle(Bow.inkSoft)
        }
        Spacer()
        Text(snapshot.map { BudgetMoney.formatted($0.available(for: envelope.id), currencyCode: currencyCode) } ?? "…")
          .font(.bowAmountSm)
          .monospacedDigit()
          .foregroundStyle(Bow.inkSoft)
        Image(systemName: "chevron.right")
          .font(.bowCaption.weight(.semibold))
          .foregroundStyle(Bow.inkFaint)
          .accessibilityHidden(true)
      }
      .contentShape(.rect)
    }
    .accessibilityHint("Edit envelope")
  }

  private func targetSummary(_ envelope: BudgetEnvelope) -> String {
    if let goal = envelope.targetMinor, goal > 0, let date = envelope.targetDate {
      return "Goal \(BudgetMoney.formatted(goal, currencyCode: currencyCode)) by \(date.formatted(.dateTime.month(.abbreviated).year()))"
    }
    return envelope.totalMonthlyTargetMinor.map {
      "Target \(BudgetMoney.formatted($0, currencyCode: currencyCode)) monthly"
    } ?? "No target"
  }

  private func setHidden(_ envelope: BudgetEnvelope, _ hidden: Bool) {
    do {
      guard let snapshot else { return }
      let undo = try UndoableChanges.setHidden(
        envelope, hidden: hidden,
        availableMinor: snapshot.available(for: envelope.id), in: modelContext
      )
      toasts?.show(.deleted("\(hidden ? "Hidden" : "Unhidden") · \(envelope.name)", undo: undo))
    } catch { message = error.localizedDescription }
  }
}

private enum EnvelopeGroupEditor: Identifiable {
  case newGroup
  case editGroup(BudgetGroup)
  case newEnvelope
  case editEnvelope(BudgetEnvelope)

  var id: String {
    switch self {
    case .newGroup: "newGroup"
    case .editGroup(let group): "group-\(group.id)"
    case .newEnvelope: "newEnvelope"
    case .editEnvelope(let envelope): "envelope-\(envelope.id)"
    }
  }
}

extension EnvelopeManagementScreen {
  /// Drops dragged envelopes into place, in their own group or another one, and renumbers that group.
  /// `beforeID` nil means the end of the group.
  fileprivate func moveEnvelopes(_ sources: [UUID], to groupID: UUID, before beforeID: UUID?) {
    guard let group = groups.first(where: { $0.id == groupID }) else { return }
    let previous = envelopes.map { ($0, $0.groupID, $0.sortOrder) }
    let moving = sources.compactMap { id in
      envelopes.first { $0.id == id && !$0.isHidden && $0.paymentAccountID == nil }
    }
    guard moving.count == sources.count else { return }
    var ordered = activeEnvelopes(in: group).filter { !sources.contains($0.id) }
    let index = beforeID.flatMap { id in ordered.firstIndex { $0.id == id } } ?? ordered.count
    ordered.insert(contentsOf: moving, at: index)
    for (order, envelope) in ordered.enumerated() {
      envelope.groupID = groupID
      envelope.sortOrder = order
    }
    do { try modelContext.save() } catch {
      for (envelope, groupID, order) in previous {
        envelope.groupID = groupID
        envelope.sortOrder = order
      }
      message = error.localizedDescription
    }
  }
}

private extension View {
  /// Envelopes can be dragged to reorder them, and between groups (iOS 27).
  @ViewBuilder
  func bowEnvelopeReordering(move: @escaping ([UUID], UUID, UUID?) -> Void) -> some View {
    if #available(iOS 27.0, *) {
      reorderContainer(for: BudgetEnvelope.self, in: UUID.self) { difference in
        let beforeID: UUID?
        switch difference.destination.position {
        case .before(let id): beforeID = id
        case .end: beforeID = nil
        }
        move(difference.sources, difference.destination.collectionID, beforeID)
      }
    } else {
      self
    }
  }
}

private extension DynamicViewContent {
  @ViewBuilder
  func bowReorderable(collectionID: UUID) -> some View {
    if #available(iOS 27.0, *) {
      reorderable(collectionID: collectionID)
    } else {
      self
    }
  }
}
