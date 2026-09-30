import SwiftUI

struct BudgetScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var currencyCode: String
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var allocations: [BudgetAllocation]
  var schedules: [BudgetSchedule]
  var snapshot: BudgetSnapshot
  var previousSnapshot: BudgetSnapshot? = nil
  @Binding var selectedMonth: Date
  var returnToPresentRequest: Int = 0
  var onAddGroup: () -> Void
  var onAddEnvelope: () -> Void
  var onEditEnvelope: (UUID) -> Void
  var onImportYNAB: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var searchText = ""

  private var isPastMonth: Bool {
    (Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth)
      < (Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date())
  }

  private var summary: BudgetSummary {
    BudgetSummary(
      snapshot: snapshot, envelopes: envelopes,
      accounts: accounts, allocations: allocations
    )
  }

  private var canAdvance: Bool {
    BudgetMonthAccessPolicy().canAdvance(
      from: selectedMonth, today: Date(), assignedMinor: summary.assignedThisMonthMinor
    )
  }

  private var lastAccessibleMonth: Date {
    BudgetMonthAccessPolicy().lastAccessibleMonth(
      today: Date(), funding: allocations.map(\.monthFundingItem)
    )
  }

  private var orderedGroups: [BudgetGroup] {
    groups.filter { !$0.isSystem }.sorted { $0.sortOrder == $1.sortOrder
      ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
      : $0.sortOrder < $1.sortOrder }
  }

  private var creditCards: [BudgetAccount] {
    accounts.filter { $0.kind == .credit &&
      (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        || "credit card payments".localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.name < $1.name }
  }

  var body: some View {
    ScrollViewReader { scrollProxy in
      List {
        BudgetOverviewSection(
          summary: summary,
          currencyCode: currencyCode,
          hasCards: accounts.contains { $0.kind == .credit },
          canMove: !isPastMonth && (snapshot.readyToAssignMinor > 0
            || envelopes.contains { snapshot.available(for: $0.id) > 0 }
            || accounts.contains { $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0 }),
          isPastMonth: isPastMonth,
          onAssign: assignMoney,
          onShowCards: {
            searchText = ""
            Task { @MainActor in
              await Task.yield()
              withAnimation(.snappy) { scrollProxy.scrollTo("credit-card-payments", anchor: .top) }
            }
          }
        )

        ForEach(orderedGroups) { group in
          let matching = visibleEnvelopes(in: group)
          if !matching.isEmpty {
            Section(group.name) {
              ForEach(matching) { envelope in
                NavigationLink(value: BudgetRoute.envelope(envelope.id)) {
                  EnvelopeBudgetRow(
                    name: envelope.name,
                    availableMinor: snapshot.available(for: envelope.id),
                    cashOverspentMinor: snapshot.cashShortfall[envelope.id, default: 0],
                    creditOverspentMinor: snapshot.creditShortfall[envelope.id, default: 0],
                    assignedMinor: snapshot.assigned[envelope.id, default: 0],
                    activityMinor: snapshot.activity[envelope.id, default: 0],
                    currencyCode: currencyCode
                  )
                }
              }
            }
            .listRowBackground(Bow.card)
          }
        }

        if !searchText.isEmpty
          && orderedGroups.allSatisfy({ visibleEnvelopes(in: $0).isEmpty })
          && creditCards.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }

        if !creditCards.isEmpty {
          Section("Credit card payments") {
            ForEach(creditCards) { card in
              NavigationLink(value: BudgetRoute.cardPayment(card.id)) {
                CardPaymentRow(card: card, snapshot: snapshot, previousSnapshot: previousSnapshot, currencyCode: currencyCode)
              }
            }
          }
          .listRowBackground(Bow.card)
          .id("credit-card-payments")
        }

        if searchText.isEmpty && !isPastMonth {
          Section {
            Button("Add Envelope", systemImage: "plus", action: onAddEnvelope)
              .disabled(orderedGroups.isEmpty)
            Button("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
            Button("Import YNAB Categories", systemImage: "square.and.arrow.down", action: onImportYNAB)
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .animation(reduceMotion ? nil : .snappy, value: selectedMonth)
      .searchable(text: $searchText, prompt: "Search envelopes or groups")
      .navigationTitle(selectedMonth.formatted(.dateTime.month(.wide).year()))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Previous Month", systemImage: "chevron.left") { changeMonth(-1) }
            .labelStyle(.iconOnly)
          Button("Next Month", systemImage: "chevron.right") { changeMonth(1) }
            .labelStyle(.iconOnly)
            .disabled(!canAdvance)
            .accessibilityHint(canAdvance ? "" : "Assign money in this month to plan the next month")
        }
      }
      .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { value in
        guard abs(value.translation.width) > 90,
              abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
        changeMonth(value.translation.width < 0 ? 1 : -1)
      })
      .navigationDestination(for: BudgetRoute.self) { route in
        switch route {
        case .envelope(let id):
          if let envelope = envelopes.first(where: { $0.id == id }) {
            EnvelopeDetailScreen(
              envelope: envelope, currencyCode: currencyCode, snapshot: snapshot,
              isPastMonth: isPastMonth,
              accounts: accounts, envelopes: envelopes,
              allocations: allocations, schedules: schedules,
              onEdit: { onEditEnvelope(envelope.id) },
              onMoveMoney: onMoveMoney,
              onSelectTransaction: onSelectTransaction,
              onEditSchedule: onEditSchedule
            )
          }
        case .cardPayment(let id):
          if let card = accounts.first(where: { $0.id == id }) {
            CardPaymentDetailScreen(
              card: card, currencyCode: currencyCode, snapshot: snapshot,
              previousSnapshot: previousSnapshot,
              isPastMonth: isPastMonth,
              accounts: accounts,
              envelopes: envelopes,
              allocations: allocations, schedules: schedules,
              onMoveMoney: onMoveMoney,
              onSelectTransaction: onSelectTransaction,
              onEditSchedule: onEditSchedule
            )
          }
        }
      }
      .onChange(of: returnToPresentRequest) { _, _ in
        let current = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = current }
      }
      .onChange(of: lastAccessibleMonth) { _, _ in
        enforceMonthAccess()
      }
      .onAppear { enforceMonthAccess() }
    }
  }

  private func visibleEnvelopes(in group: BudgetGroup) -> [BudgetEnvelope] {
    envelopes.filter {
      !$0.isHidden && $0.paymentAccountID == nil && $0.groupID == group.id
        && (searchText.isEmpty || group.name.localizedCaseInsensitiveContains(searchText)
          || $0.name.localizedCaseInsensitiveContains(searchText))
    }.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
  }

  private func assignMoney() {
    guard !isPastMonth else { return }
    let first = envelopes.first(where: { !$0.isHidden && $0.paymentAccountID == nil })
    if snapshot.readyToAssignMinor > 0 {
      guard let first else { onAddEnvelope(); return }
      onMoveMoney(.readyToAssign, .envelope(first.id))
      return
    }
    let source: BudgetBucket?
    if let funded = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      source = .envelope(funded.id)
    } else if let card = accounts.first(where: {
      $0.kind == .credit && snapshot.paymentAvailable[$0.id, default: 0] > 0
    }) {
      source = .cardPayment(card.id)
    } else {
      source = nil
    }
    guard let source else { return }
    if let overspent = envelopes.first(where: { snapshot.available(for: $0.id) < 0 }) {
      onMoveMoney(source, .envelope(overspent.id))
    } else {
      onMoveMoney(source, .readyToAssign)
    }
  }

  private func changeMonth(_ amount: Int) {
    if amount > 0 && !canAdvance { return }
    guard let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
    withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = next }
  }

  private func enforceMonthAccess() {
    let viewed = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
    guard viewed > lastAccessibleMonth else { return }
    withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = lastAccessibleMonth }
  }
}

enum BudgetRoute: Hashable {
  case envelope(UUID)
  case cardPayment(UUID)
}

private struct BudgetOverviewSection: View {
  var summary: BudgetSummary
  var currencyCode: String
  var hasCards: Bool
  var canMove: Bool
  var isPastMonth: Bool
  var onAssign: () -> Void
  var onShowCards: () -> Void

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text("Ready to Assign")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Bow.inkSoft)
        Text(BudgetMoney.formatted(summary.readyToAssignMinor, currencyCode: currencyCode))
          .font(.system(.largeTitle, design: .rounded, weight: .semibold))
          .foregroundStyle(summary.readyToAssignMinor < 0 ? Bow.overInk : Bow.ink)
          .minimumScaleFactor(0.7)
          .lineLimit(1)
          .fontDesign(.rounded).monospacedDigit()
        Text(summary.readyToAssignMinor < 0
          ? "Move money back or add cash to cover this deficit."
          : isPastMonth ? "View only · Past budget month" : "Cash available to give a job.")
          .font(.footnote)
          .foregroundStyle(Bow.inkSoft)
        Button("Move Money", systemImage: "arrow.left.arrow.right", action: onAssign)
          .bowPrimaryButton()
          .disabled(!canMove)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)
      .accessibilityElement(children: .contain)

      HStack(spacing: 16) {
        metric("Assigned", amount: summary.assignedThisMonthMinor, emphasized: false)
        Divider()
        metric("Overspent", amount: summary.overspentMinor, emphasized: summary.overspentMinor > 0)
      }
      .padding(.vertical, 6)

      LabeledContent("Assigned in future months") {
        Text(BudgetMoney.formatted(summary.assignedInFutureMinor, currencyCode: currencyCode))
          .fontDesign(.rounded).monospacedDigit()
      }
        .font(.subheadline)

      if hasCards {
        Button(action: onShowCards) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(summary.creditUncoveredMinor == 0 ? "Credit payments fully funded" : "Credit debt needs funding")
                .font(.subheadline.weight(.semibold))
              Text(summary.creditUncoveredMinor == 0
                ? "Payment money is set aside for current debt."
                : "\(BudgetMoney.formatted(summary.creditUncoveredMinor, currencyCode: currencyCode)) of card debt is uncovered")
                .font(.caption)
                .foregroundStyle(Bow.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Bow.inkSoft)
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .listRowBackground(Bow.card)
  }

  private func metric(_ title: String, amount: Int64, emphasized: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(Bow.inkSoft)
      Text(BudgetMoney.formatted(amount, currencyCode: currencyCode))
        .font(.headline)
        .foregroundStyle(emphasized ? Bow.overInk : Bow.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .fontDesign(.rounded).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

private struct EnvelopeBudgetRow: View {
  var name: String
  var availableMinor: Int64
  var cashOverspentMinor: Int64
  var creditOverspentMinor: Int64
  var assignedMinor: Int64
  var activityMinor: Int64
  var currencyCode: String

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(name).foregroundStyle(Bow.ink)
        Text(availableMinor < 0
          ? (cashOverspentMinor > 0 ? "Cash overspent" : creditOverspentMinor > 0 ? "Credit overspent · adds debt" : "Overspent")
          : "Assigned \(BudgetMoney.formatted(assignedMinor, currencyCode: currencyCode)) · Activity \(BudgetMoney.formatted(activityMinor, currencyCode: currencyCode))")
          .font(.caption)
          .foregroundStyle(availableMinor < 0 ? Bow.overInk : Bow.inkSoft)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(availableMinor, currencyCode: currencyCode))
        .fontWeight(.semibold)
        .foregroundStyle(availableMinor < 0 ? Bow.overInk : Bow.ink)
        .fontDesign(.rounded).monospacedDigit()
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

private struct CardPaymentRow: View {
  var card: BudgetAccount
  var snapshot: BudgetSnapshot
  var previousSnapshot: BudgetSnapshot?
  var currencyCode: String

  var body: some View {
    let owed = max(0, -snapshot.accountBalances[card.id, default: 0])
    let reserved = max(0, snapshot.paymentAvailable[card.id, default: 0])
    let previousOwed = max(0, -(previousSnapshot?.accountBalances[card.id] ?? 0))
    let previousReserved = max(0, previousSnapshot?.paymentAvailable[card.id] ?? 0)
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(card.name).foregroundStyle(Bow.ink)
        Text(owed > reserved
          ? (previousOwed > previousReserved
            ? "Carrying \(BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)) of debt"
            : "Credit spending needs funding")
          : "Ready to pay in full")
          .font(.caption)
          .foregroundStyle(owed > reserved ? Bow.needsInk : Bow.inkSoft)
      }
      Spacer()
      Text(BudgetMoney.formatted(reserved, currencyCode: currencyCode))
        .fontWeight(.semibold)
        .fontDesign(.rounded).monospacedDigit()
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
