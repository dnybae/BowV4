import SwiftUI

struct BudgetScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var currencyCode: String
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var allocations: [BudgetAllocation]
  var transactions: [BudgetTransaction]
  var schedules: [BudgetSchedule]
  var snapshot: BudgetSnapshot
  @Binding var selectedMonth: Date
  var onAddGroup: () -> Void
  var onAddEnvelope: () -> Void
  var onEditEnvelope: (UUID) -> Void
  var onImportYNAB: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void
  var onSelectTransaction: (UUID) -> Void
  var onEditSchedule: (UUID) -> Void
  @State private var searchText = ""
  @State private var monthDirection = 1

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

  private var previousSnapshot: BudgetSnapshot? {
    guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else { return nil }
    return BudgetLedger.snapshot(month: previous, accounts: accounts, envelopes: envelopes,
                                 allocations: allocations, transactions: transactions)
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
                NavigationLink {
                  EnvelopeDetailScreen(
                    envelope: envelope, currencyCode: currencyCode, snapshot: snapshot,
                    isPastMonth: isPastMonth,
                    accounts: accounts, envelopes: envelopes,
                    allocations: allocations, transactions: transactions, schedules: schedules,
                    onEdit: { onEditEnvelope(envelope.id) },
                    onMoveMoney: onMoveMoney,
                    onSelectTransaction: onSelectTransaction,
                    onEditSchedule: onEditSchedule
                  )
                } label: {
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
          }
        }

        if !searchText.isEmpty
          && orderedGroups.allSatisfy({ visibleEnvelopes(in: $0).isEmpty })
          && creditCards.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }

        if !creditCards.isEmpty {
          Section("Credit Card Payments") {
            ForEach(creditCards) { card in
              NavigationLink {
                CardPaymentDetailScreen(
                  card: card, currencyCode: currencyCode, snapshot: snapshot,
                  isPastMonth: isPastMonth,
                  accounts: accounts,
                  envelopes: envelopes,
                  allocations: allocations, transactions: transactions, schedules: schedules,
                  onMoveMoney: onMoveMoney,
                  onSelectTransaction: onSelectTransaction,
                  onEditSchedule: onEditSchedule
                )
              } label: {
                CardPaymentRow(card: card, snapshot: snapshot, previousSnapshot: previousSnapshot, currencyCode: currencyCode)
              }
            }
          }
          .id("credit-card-payments")
        }

        if searchText.isEmpty && !isPastMonth {
          Section {
            Button("Add Envelope", systemImage: "plus", action: onAddEnvelope)
              .disabled(orderedGroups.isEmpty)
            Button("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
            Button("Import YNAB Categories", systemImage: "square.and.arrow.down", action: onImportYNAB)
          }
        }
      }
      .id(Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth)
      .transition(reduceMotion ? .opacity : .asymmetric(
        insertion: .opacity.combined(with: .move(edge: monthDirection > 0 ? .trailing : .leading)),
        removal: .opacity.combined(with: .move(edge: monthDirection > 0 ? .leading : .trailing))
      ))
      .searchable(text: $searchText, prompt: "Search envelopes or groups")
      .navigationTitle(selectedMonth.formatted(.dateTime.month(.wide).year()))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Previous Month", systemImage: "chevron.left") { changeMonth(-1) }
            .labelStyle(.iconOnly)
          Button("Next Month", systemImage: "chevron.right") { changeMonth(1) }
            .labelStyle(.iconOnly)
        }
      }
      .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { value in
        guard abs(value.translation.width) > 90,
              abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
        changeMonth(value.translation.width < 0 ? 1 : -1)
      })
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
    guard let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
    monthDirection = amount
    withAnimation(reduceMotion ? nil : .snappy) { selectedMonth = next }
  }
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
          .foregroundStyle(.secondary)
        Text(BudgetMoney.formatted(summary.readyToAssignMinor, currencyCode: currencyCode))
          .font(.system(.largeTitle, design: .rounded, weight: .semibold))
          .foregroundStyle(summary.readyToAssignMinor < 0 ? Color.red : Color.primary)
          .minimumScaleFactor(0.7)
          .lineLimit(1)
        Text(summary.readyToAssignMinor < 0
          ? "Move money back or add cash to cover this deficit."
          : isPastMonth ? "View only · Past budget month" : "Cash available to give a job.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button("Move Money", systemImage: "arrow.left.arrow.right", action: onAssign)
          .buttonStyle(.borderedProminent)
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

      LabeledContent("Assigned in future months", value: BudgetMoney.formatted(summary.assignedInFutureMinor, currencyCode: currencyCode))
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
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func metric(_ title: String, amount: Int64, emphasized: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(BudgetMoney.formatted(amount, currencyCode: currencyCode))
        .font(.headline)
        .foregroundStyle(emphasized ? Color.red : Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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
        Text(name).foregroundStyle(.primary)
        Text(availableMinor < 0
          ? (cashOverspentMinor > 0 ? "Cash overspent" : creditOverspentMinor > 0 ? "Credit overspent · adds debt" : "Overspent")
          : "Assigned \(BudgetMoney.formatted(assignedMinor, currencyCode: currencyCode)) · Activity \(BudgetMoney.formatted(activityMinor, currencyCode: currencyCode))")
          .font(.caption)
          .foregroundStyle(availableMinor < 0 ? Color.red : Color.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Text(BudgetMoney.formatted(availableMinor, currencyCode: currencyCode))
        .fontWeight(.semibold)
        .foregroundStyle(availableMinor < 0 ? Color.red : Color.primary)
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
        Text(card.name).foregroundStyle(.primary)
        Text(owed > reserved
          ? (previousOwed > previousReserved
            ? "Carrying \(BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)) of debt"
            : "Credit spending needs funding")
          : "Ready to pay in full")
          .font(.caption)
          .foregroundStyle(owed > reserved ? Color.orange : Color.secondary)
      }
      Spacer()
      Text(BudgetMoney.formatted(reserved, currencyCode: currencyCode))
        .fontWeight(.semibold)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
