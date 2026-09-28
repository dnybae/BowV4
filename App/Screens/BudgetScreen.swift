import SwiftUI

struct BudgetScreen: View {
  var currencyCode: String
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  var accounts: [BudgetAccount]
  var snapshot: BudgetSnapshot
  @Binding var selectedMonth: Date
  var onAddGroup: () -> Void
  var onAddEnvelope: () -> Void
  var onImportYNAB: () -> Void
  var onMoveMoney: (BudgetBucket, BudgetBucket) -> Void

  private var orderedGroups: [BudgetGroup] {
    groups.sorted {
      $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
    }
  }

  private var creditCards: [BudgetAccount] {
    accounts.filter { $0.kind == .credit }.sorted { $0.name < $1.name }
  }

  private var totalOverspent: Int64 {
    snapshot.cashShortfall.values.reduce(0, +)
      + snapshot.creditShortfall.values.reduce(0, +)
  }

  private var readyStatusMessage: String {
    if totalOverspent > 0 {
      return "\(BudgetMoney.formatted(totalOverspent, currencyCode: currencyCode)) overspent in envelopes"
    }
    if snapshot.readyToAssignMinor < 0 {
      return "Cover this shortfall before assigning more money."
    }
    return "Cash waiting for a job."
  }

  private var deficitCoverSource: BudgetBucket? {
    if let envelope = envelopes.first(where: { snapshot.available(for: $0.id) > 0 }) {
      return .envelope(envelope.id)
    }
    if let card = creditCards.first(where: {
      snapshot.paymentAvailable[$0.id, default: 0] > 0
    }) {
      return .cardPayment(card.id)
    }
    return nil
  }

  private var deficitCoverTarget: BudgetBucket {
    if let overspent = envelopes.first(where: {
      snapshot.cashShortfall[$0.id, default: 0] > 0
    }) {
      return .envelope(overspent.id)
    }
    return .readyToAssign
  }

  var body: some View {
    List {
      Section {
        HStack {
          Button("Previous Month", systemImage: "chevron.left") {
            changeMonth(-1)
          }
          .labelStyle(.iconOnly)
          Spacer()
          Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
            .font(.headline)
          Spacer()
          Button("Next Month", systemImage: "chevron.right") {
            changeMonth(1)
          }
          .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
      }

      Section {
        VStack(alignment: .leading, spacing: 8) {
          Label("Ready to Assign", systemImage: "scope")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Text(BudgetMoney.formatted(snapshot.readyToAssignMinor, currencyCode: currencyCode))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(snapshot.readyToAssignMinor < 0 ? Color.red : Color.primary)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
          Text(readyStatusMessage)
            .font(.footnote)
            .foregroundStyle(totalOverspent > 0 || snapshot.readyToAssignMinor < 0
              ? Color.red : Color.secondary)
          if snapshot.readyToAssignMinor < 0 {
            if let deficitCoverSource {
              Button(deficitCoverTarget == .readyToAssign ? "Cover Deficit" : "Cover Overspending",
                     systemImage: "arrow.uturn.backward") {
                onMoveMoney(deficitCoverSource, deficitCoverTarget)
              }
              .padding(.top, 4)
            } else {
              Text("Add cash to clear this deficit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          } else {
            Button("Assign Money", systemImage: "arrow.right") {
              onMoveMoney(.readyToAssign, .envelope(envelopes.first?.id ?? UUID()))
            }
            .disabled(envelopes.isEmpty || snapshot.readyToAssignMinor <= 0)
            .padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
      }

      ForEach(orderedGroups) { group in
        Section(group.name) {
          ForEach(envelopes
            .filter { $0.groupID == group.id }
            .sorted { $0.sortOrder < $1.sortOrder }) { envelope in
              EnvelopeBudgetRow(
                envelope: envelope,
                currencyCode: currencyCode,
                snapshot: snapshot
              ) {
                onMoveMoney(.readyToAssign, .envelope(envelope.id))
              }
            }
        }
      }

      if !creditCards.isEmpty {
        Section("Credit Card Payments") {
          ForEach(creditCards) { card in
            Button {
              onMoveMoney(.readyToAssign, .cardPayment(card.id))
            } label: {
              HStack {
                Image(systemName: "creditcard.fill")
                  .foregroundStyle(.tint)
                  .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                  Text(card.name)
                    .foregroundStyle(.primary)
                  let owed = max(0, -snapshot.accountBalances[card.id, default: 0])
                  let reserved = max(0, snapshot.paymentAvailable[card.id, default: 0])
                  Text(owed > reserved
                    ? "\(BudgetMoney.formatted(owed - reserved, currencyCode: currencyCode)) unfunded debt"
                    : "Reserved for payment")
                    .font(.caption)
                    .foregroundStyle(owed > reserved ? Color.orange : Color.secondary)
                }
                Spacer()
                Text(BudgetMoney.formatted(
                  snapshot.paymentAvailable[card.id, default: 0],
                  currencyCode: currencyCode
                ))
                .foregroundStyle(snapshot.paymentAvailable[card.id, default: 0] < 0
                  ? Color.red : Color.primary)
                .fontWeight(.semibold)
              }
            }
          }
        }
      }

      Section {
        Button("Add Envelope", systemImage: "plus", action: onAddEnvelope)
          .disabled(groups.isEmpty)
        Button("Add Group", systemImage: "folder.badge.plus", action: onAddGroup)
        Button("Import YNAB Categories", systemImage: "square.and.arrow.down", action: onImportYNAB)
      }
    }
    .navigationTitle("Budget")
  }

  private func changeMonth(_ amount: Int) {
    if let next = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) {
      selectedMonth = next
    }
  }
}

private struct EnvelopeBudgetRow: View {
  var envelope: BudgetEnvelope
  var currencyCode: String
  var snapshot: BudgetSnapshot
  var onSelect: () -> Void

  private var available: Int64 { snapshot.available(for: envelope.id) }

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        Image(systemName: envelope.symbol)
          .font(.body)
          .foregroundStyle(.tint)
          .frame(width: 32, height: 32)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(envelope.name)
            .foregroundStyle(.primary)
          if available < 0 {
            Text("Overspent · Tap to cover")
              .font(.caption)
              .foregroundStyle(.red)
          } else {
            Text("Assigned \(BudgetMoney.formatted(snapshot.assigned[envelope.id, default: 0], currencyCode: currencyCode)) · Activity \(BudgetMoney.formatted(snapshot.activity[envelope.id, default: 0], currencyCode: currencyCode))")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
        }
        Spacer(minLength: 8)
        Text(BudgetMoney.formatted(available, currencyCode: currencyCode))
          .fontWeight(.semibold)
          .foregroundStyle(available < 0 ? Color.red : Color.primary)
      }
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(envelope.name), available \(BudgetMoney.formatted(available, currencyCode: currencyCode))")
    .accessibilityHint("Opens money movement")
  }
}
