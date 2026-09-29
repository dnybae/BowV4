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
  @State private var didSuggestEnvelope = false

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
        Text(record.origin == .bankFile ? "From a bank file" : "Posted at your bank")
      } footer: {
        Text(record.status == .imported
          ? "Choose what this imported transaction represents. Your choice completes the review."
          : "This bank item is not in your budget yet. Choose what it represents to complete the review.")
      }

      if relatedSchedule?.kind == .transfer,
         let relatedOccurrence, let relatedSchedule {
        Section {
          if candidates.contains(where: { $0.scheduleID == relatedSchedule.id }) {
            Text("The scheduled transfer is recorded. Confirm its match below.")
              .foregroundStyle(.secondary)
          } else {
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
          }
        } header: { Text("Scheduled transfer") }
      }

      if !candidates.isEmpty {
        Section {
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
        if case .match(let id) = selected,
           record.amountMinor < 0,
           candidates.first(where: { $0.id == id })?.envelopeID == nil {
          CategorySelectionField(
            title: "Envelope", selection: $envelopeID,
            envelopes: envelopes, noneTitle: "Choose an Envelope"
          )
        }
        } header: {
          Text("Match an existing transaction")
        } footer: {
          Text("Matching keeps your existing payee, envelope, and notes. You can unmatch it later.")
        }
      }

      if relatedSchedule?.kind != .transfer
        && !(record.status == .review && record.transactionID.map { id in
          candidates.contains { $0.id == id }
        } == true) {
        Section {
          if !candidates.isEmpty && record.status != .imported {
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
          } else if record.amountMinor >= 0 {
            Text("This income will go to Ready to Assign.")
              .foregroundStyle(.secondary)
          }
          if selected == .addNew, record.amountMinor < 0 {
            CategorySelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Choose an Envelope"
            )
          }
        } header: {
          Text(record.status == .imported ? "Complete review" : "Add to Spending")
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
        .disabled(selected == nil || needsEnvelope)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
    .task(id: record.id) { loadCandidates() }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      loadCandidates()
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
    case .addNew: record.status == .imported ? "Complete Review" : "Add Transaction"
    case nil: "Choose an Option"
    }
  }

  private var needsEnvelope: Bool {
    guard record.amountMinor < 0 else { return false }
    switch selected {
    case .addNew: return envelopeID == nil
    case .match(let id):
      return candidates.first(where: { $0.id == id })?.envelopeID == nil
        && envelopeID == nil
    case nil: return false
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

  private func loadCandidates() {
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
      if record.status == .imported {
        selected = .addNew
      } else if let id = record.transactionID, candidates.contains(where: { $0.id == id }) {
        selected = .match(id)
      } else if relatedSchedule?.kind == .transfer,
                let scheduleID = relatedSchedule?.id,
                let candidate = candidates.first(where: { $0.scheduleID == scheduleID }) {
        selected = .match(candidate.id)
      } else if candidates.isEmpty && relatedSchedule?.kind != .transfer {
        selected = .addNew
      } else if case .match(let id) = selected,
                !candidates.contains(where: { $0.id == id }) {
        selected = nil
      }
      if !didSuggestEnvelope {
        didSuggestEnvelope = true
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
      }
    } catch {
      message = error.localizedDescription
    }
  }
}

private enum BankReviewChoice: Equatable {
  case match(UUID)
  case addNew
}
