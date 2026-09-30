import SwiftUI
import SwiftData

struct CategoryManagementScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.budgetSnapshotRepository) private var sharedRepository
  @Query private var profiles: [BudgetProfile]
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var accounts: [BudgetAccount]
  @Query private var allocations: [BudgetAllocation]
  @Query private var schedules: [BudgetSchedule]
  @Query private var payees: [BudgetPayee]
  @State private var editor: CategoryEditor?
  @State private var pendingHide: BudgetEnvelope?
  @State private var pendingDelete: BudgetEnvelope?
  @State private var movingEnvelope: BudgetEnvelope?
  @State private var message: String?
  @State private var snapshot: BudgetSnapshot?
  @State private var usedEnvelopeIDs: Set<UUID> = []
  @State private var historyLoaded = false
  @State private var refreshVersion = 0

  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }
  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted {
      $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
    }
  }
  private var hiddenEnvelopes: [BudgetEnvelope] {
    envelopes.filter { $0.isHidden && $0.paymentAccountID == nil }.sorted { $0.name < $1.name }
  }

  private var showHideConfirmation: Binding<Bool> {
    Binding(get: { pendingHide != nil }, set: { if !$0 { pendingHide = nil } })
  }

  private var showDeleteConfirmation: Binding<Bool> {
    Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
  }

  private var showMessage: Binding<Bool> {
    Binding(get: { message != nil }, set: { if !$0 { message = nil } })
  }

  private func activeEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter { $0.groupID == group.id && $0.paymentAccountID == nil && !$0.isHidden }
      .sorted { $0.sortOrder == $1.sortOrder
        ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    List {
      Section {
        NavigationLink {
          EnvelopeDirectoryScreen()
        } label: {
          Label("Add from Envelope Directory", systemImage: "square.grid.2x2")
        }
        Button("Create Custom Envelope", systemImage: "plus") {
          editor = .newEnvelope
        }
        .disabled(orderedGroups.isEmpty)
        Button("Create Group", systemImage: "folder.badge.plus") {
          editor = .newGroup
        }
      }
      .listRowBackground(Bow.card)

      if groups.isEmpty {
        ContentUnavailableView(
          "No groups yet", systemImage: "folder",
          description: Text("Create a group to organize your envelopes.")
        )
      }

      ForEach(orderedGroups) { group in
        Section {
          Button {
            editor = .editGroup(group)
          } label: {
            HStack {
              Text(group.name).fontWeight(.semibold)
              Spacer()
              Text("Edit Group").font(.caption).foregroundStyle(Bow.inkSoft)
            }
          }
          ForEach(activeEnvelopes(in: group)) { envelope in
            envelopeRow(envelope)
          }
        } header: {
          Text(group.name)
        }
        .listRowBackground(Bow.card)
      }

      if !hiddenEnvelopes.isEmpty {
        Section("Hidden envelopes") {
          ForEach(hiddenEnvelopes) { envelope in
            envelopeRow(envelope)
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
    .navigationTitle("Manage Groups & Envelopes")
    .task(id: refreshVersion) {
      let repository = sharedRepository ?? BudgetSnapshotRepository(modelContainer: modelContext.container)
      snapshot = try? await repository.snapshot(month: Date())
      let transactionRepository = TransactionPageRepository(modelContainer: modelContext.container)
      var used: Set<UUID> = []
      for envelope in envelopes {
        if (try? await transactionRepository.hasTransaction(inEnvelope: envelope.id)) == true {
          used.insert(envelope.id)
        }
      }
      usedEnvelopeIDs = used
      historyLoaded = true
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
        EnvelopeEditorScreen(groups: orderedGroups, nextOrder: envelopes.count)
      case .editEnvelope(let envelope):
        EnvelopeEditorScreen(groups: orderedGroups, nextOrder: envelopes.count, envelope: envelope)
      }
    }
    .sheet(item: $movingEnvelope) { envelope in
      MoneyMoveScreen(
        currencyCode: currencyCode, month: Date(),
        source: .envelope(envelope.id), target: .readyToAssign
      )
    }
    .confirmationDialog("Hide envelope with money?", isPresented: showHideConfirmation) {
      Button("Move Money First") {
        movingEnvelope = pendingHide
        pendingHide = nil
      }
      Button("Hide and Keep Balance") {
        if let pendingHide { setHidden(pendingHide, true) }
        pendingHide = nil
      }
    } message: {
      if let pendingHide {
        Text("\(BudgetMoney.formatted(snapshot?.available(for: pendingHide.id) ?? 0, currencyCode: currencyCode)) will remain in this hidden envelope and in your budget.")
      }
    }
    .confirmationDialog("Delete unused envelope?", isPresented: showDeleteConfirmation) {
      Button("Delete Envelope", role: .destructive) {
        if let pendingDelete {
          do {
            try BudgetCommands.deleteUnusedEnvelope(pendingDelete, in: modelContext)
          } catch { message = error.localizedDescription }
        }
        pendingDelete = nil
      }
    } message: {
      Text("This cannot be undone.")
    }
    .alert("Envelope", isPresented: showMessage) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func envelopeRow(_ envelope: BudgetEnvelope) -> some View {
    Button {
      editor = .editEnvelope(envelope)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(envelope.name)
          if let target = envelope.totalMonthlyTargetMinor {
            Text("Target \(BudgetMoney.formatted(target, currencyCode: currencyCode))")
              .font(.caption).foregroundStyle(Bow.inkSoft)
          }
        }
        Spacer()
        Text(snapshot.map { BudgetMoney.formatted($0.available(for: envelope.id), currencyCode: currencyCode) } ?? "…")
          .font(.subheadline)
          .foregroundStyle(Bow.inkSoft)
      }
    }
    .swipeActions {
      if snapshot?.available(for: envelope.id) ?? 0 > 0 {
        Button("Move Money", systemImage: "arrow.left.arrow.right") {
          movingEnvelope = envelope
        }
      }
      if envelope.isHidden {
        Button("Unhide", systemImage: "eye") { setHidden(envelope, false) }
      } else {
        Button("Hide", systemImage: "eye.slash") {
          if snapshot?.available(for: envelope.id) ?? 0 > 0 {
            pendingHide = envelope
          } else {
            setHidden(envelope, true)
          }
        }
      }
      if !hasHistory(envelope) {
        Button("Delete", systemImage: "trash", role: .destructive) {
          pendingDelete = envelope
        }
      }
    }
    .accessibilityHint("Edit envelope. Swipe for hide or delete actions.")
  }

  private func hasHistory(_ envelope: BudgetEnvelope) -> Bool {
    !historyLoaded || usedEnvelopeIDs.contains(envelope.id)
      || allocations.contains { $0.sourceEnvelopeID == envelope.id || $0.targetEnvelopeID == envelope.id }
      || schedules.contains { $0.envelopeID == envelope.id }
      || payees.contains { $0.defaultEnvelopeID == envelope.id }
  }

  private func setHidden(_ envelope: BudgetEnvelope, _ hidden: Bool) {
    do {
      guard let snapshot else { return }
      try BudgetCommands.setEnvelopeHidden(
        envelope, hidden: hidden,
        availableMinor: snapshot.available(for: envelope.id), in: modelContext
      )
    } catch { message = error.localizedDescription }
  }
}

private enum CategoryEditor: Identifiable {
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
