import SwiftUI
import SwiftData

struct EnvelopeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var groups: [BudgetGroup]
  var nextOrder: Int
  var envelope: BudgetEnvelope?
  var layout: Layout = .envelope

  enum Layout {
    /// Name first: the envelope's name, group and target.
    case envelope
    /// Opened from the envelope's target tile: this month's target and what it adds up to.
    case target
  }
  @Query private var profiles: [BudgetProfile]
  @Query private var schedules: [BudgetSchedule]
  @State private var name = ""
  @State private var groupID: UUID?
  @State private var targetAmountMinor: Int64 = 0
  @State private var hasTargetDate = false
  @State private var targetDate = Date()
  @State private var errorMessage: String?
  @State private var initialFields: EnvelopeEditorFields?

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
    EnvelopeEditorFields(name: name, groupID: groupID, target: targetAmountMinor,
                         targetDate: hasTargetDate ? targetDate : nil)
  }

  private var hasChanges: Bool { initialFields.map { fields != $0 } ?? false }

  private var tileSymbol: String {
    TransactionIconSymbol.name(for: .expense, payee: "", envelope: name)
  }

  init(groups: [BudgetGroup], nextOrder: Int, envelope: BudgetEnvelope? = nil, layout: Layout = .envelope) {
    self.groups = groups
    self.nextOrder = nextOrder
    self.envelope = envelope
    self.layout = envelope == nil ? .envelope : layout
    _name = State(initialValue: envelope?.name ?? "")
    _groupID = State(initialValue: envelope?.groupID ?? groups.first?.id)
    _targetAmountMinor = State(initialValue: envelope?.targetMinor ?? 0)
    _hasTargetDate = State(initialValue: envelope?.targetDate != nil)
    _targetDate = State(initialValue: envelope?.targetDate ?? Date())
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
      .navigationTitle(envelope == nil ? "New envelope" : layout == .target ? "Target" : "Envelope")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
        ToolbarItem(placement: .confirmationAction) {
          Button(envelope == nil ? "Add" : "Save") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || groupID == nil)
        }
      }
      .bowErrorAlert("Couldn’t save envelope", message: $errorMessage)
    }
  }

  /// Name-first: icon and name, the group, then the target.
  private var envelopeForm: some View {
    Form {
      Section {
        BowNameHeader("Envelope name", name: $name, systemImage: tileSymbol)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
      Section {
        Picker(selection: $groupID) {
          ForEach(groups) { group in
            Text(group.name).tag(Optional(group.id))
          }
        } label: {
          Label("Group", systemImage: "square.grid.2x2").labelStyle(.bowTile)
        }
        .pickerStyle(.menu)
      }
      .listRowBackground(Bow.card)
      Section {
        CurrencyAmountField("Amount", minor: $targetAmountMinor, currencyCode: currencyCode,
                            systemImage: "dollarsign")
        Toggle(isOn: $hasTargetDate) {
          Label("Set target date", systemImage: "calendar").labelStyle(.bowTile)
        }
        if hasTargetDate {
          NavigationLink {
            BowDatePickerScreen(title: "Target date", date: $targetDate)
          } label: {
            BowTileValueRow("Target date", systemImage: "clock",
                            value: targetDate.formatted(date: .abbreviated, time: .omitted))
          }
        }
      } header: {
        Text("Target")
      } footer: {
        if let envelope, envelope.scheduledTargetMinor > 0 {
          Text("A target is a plan. It shows what to assign each month but does not move money by itself. Scheduled transactions add \(BudgetMoney.formatted(envelope.scheduledTargetMinor, currencyCode: currencyCode)) this month on top of it.")
        } else {
          Text("A target is a plan. It shows what to assign each month but does not move money by itself.")
        }
      }
      .listRowBackground(Bow.card)
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
          Picker("Group", selection: $groupID) {
            ForEach(groups) { group in
              Text(group.name).tag(Optional(group.id))
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      Section {
        CurrencyAmountField("Amount each month", minor: $targetAmountMinor, currencyCode: currencyCode,
                            style: .editorHero)
          .padding(.vertical, Bow.Space.s2)
        Toggle(isOn: $hasTargetDate) {
          Label("Set target date", systemImage: "calendar").labelStyle(.bowTile)
        }
        if hasTargetDate {
          NavigationLink {
            BowDatePickerScreen(title: "Target date", date: $targetDate)
          } label: {
            LabeledContent {
              Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(Bow.bowInk)
            } label: {
              Label("Target date", systemImage: "clock").labelStyle(.bowTile)
            }
          }
        }
      }
      .listRowBackground(Bow.card)

      Section {
        LabeledContent {
          MoneyText(minor: targetAmountMinor, currencyCode: currencyCode)
        } label: {
          Label("Your target", systemImage: "dollarsign").labelStyle(.bowTile)
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
      } footer: {
        Text("A target is a plan. It shows what to assign each month but doesn’t move money by itself.")
      }
    }
  }

  private func save() {
    guard let groupID else { return }
    guard groups.contains(where: { $0.id == groupID && !$0.isSystem }) else {
      errorMessage = "Choose a regular envelope group."
      return
    }
    do {
      if let envelope {
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
          order: nextOrder,
          targetMinor: targetMinor,
          targetDate: hasTargetDate ? targetDate : nil,
          in: modelContext
        )
      }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EnvelopeEditorFields: Equatable {
  var name: String
  var groupID: UUID?
  var target: Int64
  var targetDate: Date?
}
