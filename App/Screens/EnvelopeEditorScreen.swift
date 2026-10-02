import SwiftUI
import SwiftData

/// The one envelope editor: new envelopes, envelope ideas, editing, and the target sheet.
struct EnvelopeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  var groups: [BudgetGroup]
  var envelope: BudgetEnvelope?
  var layout: Layout = .envelope
  /// An envelope idea fills in the name and suggests a group, creating it if needed.
  var idea: EnvelopeIdea?
  var onAdded: (() -> Void)?

  enum Layout {
    /// Name first: the envelope's name, group and target.
    case envelope
    /// Opened from the envelope's target tile: this month's target and what it adds up to.
    case target
  }
  @Query private var profiles: [BudgetProfile]
  @Query private var schedules: [BudgetSchedule]
  @State private var name = ""
  @State private var groupChoice: EnvelopeGroupChoice?
  @State private var targetAmountMinor: Int64 = 0
  @State private var hasTargetDate = false
  @State private var targetDate = Date()
  @State private var errorMessage: String?
  @State private var initialFields: EnvelopeEditorFields?
  @FocusState private var nameIsFocused: Bool
  @State private var didRequestNameFocus = false

  private var targetMinor: Int64? { targetAmountMinor > 0 ? targetAmountMinor : nil }
  private var currencyCode: String { profiles.first?.currencyCode ?? "USD" }

  /// Scheduled transactions that add to this month's target, as on the envelope's detail screen.
  private var scheduledContributions: [ScheduleTargetContribution] {
    guard let envelope else { return [] }
    return ScheduleTargetCalculator().contributions(for: envelope.id, schedules: schedules, month: Date())
  }

  /// Your target plus scheduled transactions: what the footnote used to describe.
  private var fundThisMonthMinor: Int64 {
    targetAmountMinor + scheduledContributions.reduce(0) { $0 + $1.totalMinor }
  }

  private var fields: EnvelopeEditorFields {
    EnvelopeEditorFields(name: name, group: groupChoice, target: targetAmountMinor,
                         targetDate: hasTargetDate ? targetDate : nil)
  }

  private var hasChanges: Bool { initialFields.map { fields != $0 } ?? false }

  private var tileSymbol: String {
    TransactionIconSymbol.name(for: .expense, payee: "", envelope: name)
  }

  private var isNew: Bool { envelope == nil }

  init(groups: [BudgetGroup], envelope: BudgetEnvelope? = nil, layout: Layout = .envelope,
       idea: EnvelopeIdea? = nil, onAdded: (() -> Void)? = nil) {
    self.groups = groups.filter { !$0.isSystem }
      .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
    self.envelope = envelope
    self.layout = envelope == nil ? .envelope : layout
    self.idea = idea
    self.onAdded = onAdded
    _name = State(initialValue: envelope?.name ?? idea?.name ?? "")
    let initialGroup: EnvelopeGroupChoice?
    if let envelope {
      initialGroup = .existing(envelope.groupID)
    } else if let idea {
      initialGroup = self.groups.first {
        $0.name.localizedCaseInsensitiveCompare(idea.groupName) == .orderedSame
      }.map { .existing($0.id) } ?? .new(idea.groupName)
    } else {
      initialGroup = self.groups.first.map { .existing($0.id) }
    }
    _groupChoice = State(initialValue: initialGroup)
    _targetAmountMinor = State(initialValue: envelope?.targetMinor ?? 0)
    _hasTargetDate = State(initialValue: envelope?.targetDate != nil)
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
        case .target: targetForm
        }
      }
      .bowSkyList(mood: .dawn, height: 420)
      .bowEditorSheet(hasChanges: hasChanges)
      .onAppear { if initialFields == nil { initialFields = fields } }
      .navigationTitle(isNew ? (idea == nil ? "New envelope" : "Add envelope") : layout == .target ? "Target" : "Envelope")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
        ToolbarItem(placement: .confirmationAction) {
          Button { save() } label: { BowToolbarLabel(isNew ? "Add" : "Save") }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || groupChoice == nil || (!isNew && !hasChanges))
        }
      }
      .bowErrorAlert("Couldn’t save envelope", message: $errorMessage)
    }
  }

  private var groupPicker: some View {
    Picker(selection: $groupChoice) {
      ForEach(groups) { group in
        Text(group.name).tag(Optional(EnvelopeGroupChoice.existing(group.id)))
      }
      if let idea, !groups.contains(where: {
        $0.name.localizedCaseInsensitiveCompare(idea.groupName) == .orderedSame
      }) {
        Text("New group: \(idea.groupName)").tag(Optional(EnvelopeGroupChoice.new(idea.groupName)))
      }
    } label: {
      Label("Group", systemImage: "folder").labelStyle(.bowTile)
    }
    .pickerStyle(.menu)
  }

  /// Name first, followed by the group and target.
  private var envelopeForm: some View {
    Form {
      Section {
        BowNameHeader(placeholder: "Envelope name", name: $name, isFocused: $nameIsFocused) {
          BowGlossyTile(systemImage: tileSymbol)
        }
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
        groupPicker
      }
      .listRowBackground(Bow.card)
      targetSection(amountTitle: "Monthly target")
    }
  }

  /// The target sheet: context card, this month's amount, and what it adds up to.
  private var targetForm: some View {
    Form {
      Section {
        BowContextCard {
          BowGlossyTile(systemImage: tileSymbol, size: 44)
        } title: {
          VStack(alignment: .leading, spacing: 2) {
            TextField("Name", text: $name)
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
              .accessibilityLabel("Envelope name")
            Text("Envelope name")
              .font(.bowSubhead)
              .foregroundStyle(Bow.inkSoft)
              .accessibilityHidden(true)
          }
        } trailing: {
          groupPicker
            .labelsHidden()
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      targetSection(amountTitle: "Monthly target", isHero: true)

      Section {
        LabeledContent {
          MoneyText(minor: targetAmountMinor, currencyCode: currencyCode)
        } label: {
          Label(hasTargetDate ? "Toward your goal" : "Your target", systemImage: "dollarsign").labelStyle(.bowTile)
        }
        .listRowBackground(Bow.card)
        ForEach(scheduledContributions) { contribution in
          ScheduledTargetRow(contribution: contribution, currencyCode: currencyCode)
            .listRowBackground(Bow.card)
        }
        LabeledContent {
          MoneyText(minor: fundThisMonthMinor, currencyCode: currencyCode)
            .font(.bowTitle)
            .foregroundStyle(Bow.ink)
        } label: {
          Text("Fund this month")
            .font(.bowHeadline)
            .foregroundStyle(Bow.ink)
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(Bow.bowTint)
      } header: {
        Text("This month")
      }
    }
  }

  /// A monthly amount, or, with a date, a goal to reach by then.
  @ViewBuilder
  private func targetSection(amountTitle: String, isHero: Bool = false) -> some View {
    Section {
      Toggle(isOn: $hasTargetDate.animation()) {
        Label("Save by a date", systemImage: "flag.checkered").labelStyle(.bowTile)
      }
      if isHero {
        CurrencyAmountField(hasTargetDate ? "Goal amount" : amountTitle, minor: $targetAmountMinor,
                            currencyCode: currencyCode, style: .editorHero)
          .padding(.vertical, Bow.Space.s2)
      } else {
        CurrencyAmountField(hasTargetDate ? "Goal amount" : amountTitle, minor: $targetAmountMinor,
                            currencyCode: currencyCode, systemImage: "dollarsign")
      }
      if hasTargetDate {
        NavigationLink {
          BowDatePickerScreen(title: "Goal date", date: $targetDate, range: Date()...Date.distantFuture)
        } label: {
          BowTileValueRow("Goal date", systemImage: "calendar",
                          value: targetDate.formatted(.dateTime.month(.wide).year()))
        }
      }
    } header: {
      Text("Target")
    } footer: {
      Text(targetFootnote)
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }

  private var targetFootnote: String {
    if hasTargetDate {
      return "Bow spreads what’s left of the goal across the months until \(targetDate.formatted(.dateTime.month(.wide).year())) and shows how much to assign each month. A target never moves money by itself."
    }
    if let envelope, envelope.scheduledTargetMinor > 0 {
      return "A target is what to assign each month; it never moves money by itself. Scheduled bills add \(BudgetMoney.formatted(envelope.scheduledTargetMinor, currencyCode: currencyCode)) this month on top of it."
    }
    return "A target is what to assign each month; it never moves money by itself."
  }

  private func save() {
    guard let groupChoice else { return }
    do {
      let groupID: UUID
      switch groupChoice {
      case .existing(let id):
        guard groups.contains(where: { $0.id == id }) else {
          errorMessage = "Choose a regular envelope group."
          return
        }
        groupID = id
      case .new(let groupName):
        let group = BudgetGroup(name: groupName, sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(group)
        groupID = group.id
      }
      if let envelope {
        if envelope.groupID != groupID {
          envelope.sortOrder = try BudgetCommands.nextEnvelopeOrder(in: groupID, context: modelContext)
        }
        envelope.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        envelope.groupID = groupID
        envelope.targetMinor = targetMinor
        envelope.targetDate = hasTargetDate ? targetDate : nil
        try modelContext.save()
      } else {
        try BudgetCommands.addEnvelope(
          name: name,
          symbol: "",
          groupID: groupID,
          targetMinor: targetMinor,
          targetDate: hasTargetDate ? targetDate : nil,
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

enum EnvelopeGroupChoice: Hashable {
  case existing(UUID)
  case new(String)
}

/// A suggested envelope from Envelope ideas.
struct EnvelopeIdea: Identifiable, Hashable {
  var name: String
  var groupName: String
  var id: String { groupName + "/" + name }
}

private struct EnvelopeEditorFields: Equatable {
  var name: String
  var group: EnvelopeGroupChoice?
  var target: Int64
  var targetDate: Date?
}
