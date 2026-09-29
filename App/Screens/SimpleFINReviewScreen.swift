import SwiftUI
import SwiftData

struct SimpleFINReviewScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var accounts: [BudgetAccount]
  @Query private var envelopes: [BudgetEnvelope]
  @Query private var payees: [BudgetPayee]
  var record: SimpleFINImportRecord
  var relatedOccurrence: BudgetScheduleOccurrence? = nil
  var relatedSchedule: BudgetSchedule? = nil
  var onRecordScheduledTransfer: ((ScheduledTransactionDraft) -> Void)? = nil
  @State private var selected: BankReviewChoice?
  @State private var envelopeID: UUID?
  @State private var message: String?
  @State private var candidates: [BudgetTransaction] = []
  @State private var showingIgnoreConfirmation = false

  private var account: BudgetAccount? { accounts.first { $0.id == record.localAccountID } }
  private var currencyCode: String { account?.currencyCode ?? "USD" }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(record.payee.isEmpty ? "Bank transaction" : record.payee)
            .font(.title3.weight(.semibold))
          Text(BudgetMoney.formatted(record.amountMinor, currencyCode: currencyCode))
            .font(.title2.weight(.bold))
          Text("\(account?.name ?? "Account") · \(record.date.formatted(date: .abbreviated, time: .omitted))")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
      } header: {
        Text("Posted at your bank")
      } footer: {
        Text(record.status == .imported
          ? "Choose what this imported transaction represents. Your choice completes the review."
          : "This bank item is not in your budget yet. Choose what it represents to complete the review.")
      }

      if relatedSchedule?.kind == .transfer,
         let relatedOccurrence, let relatedSchedule {
        Section {
          Text("Record the scheduled transfer first, then match this bank transaction to it.")
            .foregroundStyle(.secondary)
          Button("Record Scheduled Transfer", systemImage: "arrow.left.arrow.right") {
            onRecordScheduledTransfer?(ScheduledTransactionDraft(
              scheduleID: relatedSchedule.id,
              scheduledFor: relatedOccurrence.scheduledFor,
              accountID: relatedSchedule.accountID,
              transferAccountID: relatedSchedule.transferAccountID,
              envelopeID: relatedSchedule.envelopeID, kind: .transfer,
              amountMinor: relatedSchedule.amountMinor, payee: relatedSchedule.payee,
              notes: relatedSchedule.notes, date: relatedOccurrence.scheduledFor
            ))
          }
        } header: { Text("Scheduled transfer") }
      }

      Section {
        if candidates.isEmpty {
          Text("No existing transaction looks like this bank item.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(candidates) { candidate in
          Button {
            selected = .match(candidate.id)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: selected == .match(candidate.id)
                ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text(candidate.payee.isEmpty ? "Transfer" : candidate.payee)
                  .foregroundStyle(.primary)
                Text(candidate.date.formatted(date: .abbreviated, time: .omitted))
                  .font(.caption).foregroundStyle(.secondary)
                if candidate.amountMinor != record.amountMinor {
                  Text("Amount differs; matching uses the posted bank amount")
                    .font(.caption).foregroundStyle(.orange)
                }
              }
              Spacer(minLength: 6)
              Text(BudgetMoney.formatted(
                candidate.transferAccountID == record.localAccountID
                  ? -candidate.amountMinor : candidate.amountMinor,
                currencyCode: currencyCode
              ))
                .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected == .match(candidate.id) ? .isSelected : [])
        }
      } header: {
        Text("Match an existing transaction")
      } footer: {
        Text("Matching keeps the payee, category, and notes you entered. It creates one transaction, and you can unmatch it later.")
      }

      if relatedSchedule?.kind != .transfer {
        Section {
          Button {
            selected = .addNew
          } label: {
            HStack(spacing: 12) {
              Image(systemName: selected == .addNew ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text("Add as new transaction")
                  .foregroundStyle(.primary)
                Text("Use this if you have not entered it before")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected == .addNew ? .isSelected : [])
          if selected == .addNew, record.amountMinor < 0 {
            CategorySelectionField(
              title: "Category", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Needs Categorization"
            )
          }
        }
      }

      Section {
        Button("Ignore Bank Transaction", role: .destructive) {
          showingIgnoreConfirmation = true
        }
      } footer: {
        Text("Ignore only if this bank item should not appear in your budget.")
      }
    }
    .navigationTitle("Review Transaction")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button {
        confirm()
      } label: {
        Text(primaryTitle)
          .frame(maxWidth: .infinity)
      }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selected == nil)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
    .task(id: record.id) {
      do {
        let nearby = try BudgetTransactionLookup.near(
          accountID: record.localAccountID, date: record.date, days: 10, in: modelContext
        )
        let records = try modelContext.fetch(FetchDescriptor<SimpleFINImportRecord>())
        let matches = SimpleFINSyncCoordinator.shared.possibleMatches(
          for: record, among: nearby, records: records
        )
        candidates = relatedSchedule?.kind == .transfer
          ? matches.filter { $0.kind == .transfer } : matches
        if candidates.isEmpty && relatedSchedule?.kind != .transfer { selected = .addNew }
        envelopeID = relatedSchedule?.envelopeID
        if envelopeID == nil {
          let rules = PayeeDirectory.ruleItems(
            payees: payees,
            validEnvelopeIDs: Set(envelopes.filter {
              !$0.isHidden && $0.paymentAccountID == nil
            }.map(\.id))
          )
          envelopeID = PayeeRuleMatcher().envelopeID(for: record.payee, rules: rules)
        }
      } catch {
        message = error.localizedDescription
      }
    }
    .confirmationDialog("Ignore this bank transaction?", isPresented: $showingIgnoreConfirmation) {
      Button("Ignore Transaction", role: .destructive) { resolve(.ignore) }
    } message: {
      Text("It will not appear in Spending or affect your budget.")
    }
    .alert("Could Not Complete Review", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private var primaryTitle: String {
    switch selected {
    case .match: "Confirm Match"
    case .addNew: "Add Transaction"
    case nil: "Choose an Option"
    }
  }

  private func confirm() {
    switch selected {
    case .match(let id): resolve(.link(id))
    case .addNew: resolve(.importNew)
    case nil: break
    }
  }

  private func resolve(_ decision: SimpleFINReviewDecision) {
    do {
      try SimpleFINSyncCoordinator.shared.resolve(
        record, as: decision, envelopeID: envelopeID,
        scheduleID: relatedOccurrence?.scheduleID,
        scheduledFor: relatedOccurrence?.scheduledFor,
        in: modelContext
      )
      dismiss()
    } catch {
      message = error.localizedDescription
    }
  }
}

private enum BankReviewChoice: Equatable {
  case match(UUID)
  case addNew
}
