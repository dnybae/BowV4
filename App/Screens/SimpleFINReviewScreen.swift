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
        HStack(spacing: Bow.Space.s3) {
          MerchantLogoView(
            merchantName: record.payee,
            domain: PayeeDirectory.logoDomain(for: record.payee, transactionDomain: nil, payees: payees),
            kind: record.amountMinor < 0 ? .expense : .inflow,
            categoryName: nil
          )
          VStack(alignment: .leading, spacing: 2) {
            Text(record.payee.isEmpty ? "Bank transaction" : record.payee)
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            Text("\(account?.name ?? "Account") · \(record.date.formatted(date: .abbreviated, time: .omitted))")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
          }
          Spacer(minLength: Bow.Space.s2)
          Text(BudgetMoney.formatted(record.amountMinor, currencyCode: currencyCode))
            .font(.bowTitle)
            .monospacedDigit()
            .foregroundStyle(Bow.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, Bow.Space.s2)
        .accessibilityElement(children: .combine)
      } header: {
        Text(record.origin == .bankFile ? "From a bank file" : "Posted at your bank")
      } footer: {
        Text(record.status == .imported
          ? "Choose what this imported transaction represents. Your choice completes the review."
          : "This bank item is not in your budget yet. Choose what it represents to complete the review.")
      }
      .listRowBackground(Bow.card)

      if relatedSchedule?.kind == .transfer,
         let relatedOccurrence, let relatedSchedule {
        Section {
          if candidates.contains(where: { $0.scheduleID == relatedSchedule.id }) {
            Text("The scheduled transfer is recorded. Confirm its match below.")
              .foregroundStyle(Bow.inkSoft)
          } else {
            Text("Record the scheduled transfer first, then match this bank transaction to it.")
              .foregroundStyle(Bow.inkSoft)
            Button("Record scheduled transfer", systemImage: "arrow.left.arrow.right") {
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
        .listRowBackground(Bow.card)
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
                  .foregroundStyle(Bow.ink)
                Text(candidate.date.formatted(date: .abbreviated, time: .omitted))
                  .font(.caption).foregroundStyle(Bow.inkSoft)
                if candidate.amountMinor != record.amountMinor {
                  Text("Amount differs; matching uses the posted bank amount")
                    .font(.caption).foregroundStyle(Bow.needsInk)
                }
              }
              Spacer(minLength: 6)
              Text(BudgetMoney.formatted(
                candidate.transferAccountID == record.localAccountID
                  ? -candidate.amountMinor : candidate.amountMinor,
                currencyCode: currencyCode
              ))
                .foregroundStyle(Bow.ink)
                .fontDesign(.rounded).monospacedDigit()
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
            envelopes: envelopes, noneTitle: "Choose an envelope"
          )
        }
        } header: {
          Text("Match an existing transaction")
        } footer: {
          Text("Matching keeps your existing payee, envelope, and notes. You can unmatch it later.")
        }
        .listRowBackground(Bow.card)
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
                    .foregroundStyle(Bow.ink)
                  Text("Use this if you have not entered it before")
                    .font(.caption).foregroundStyle(Bow.inkSoft)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected == .addNew ? .isSelected : [])
          } else if record.amountMinor >= 0 {
            Text("This income will go to Ready to Assign.")
              .foregroundStyle(Bow.inkSoft)
          }
          if selected == .addNew, record.amountMinor < 0 {
            CategorySelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Choose an envelope"
            )
          }
        } header: {
          Text(record.status == .imported ? "Complete review" : "Add to spending")
        }
        .listRowBackground(Bow.card)
      }

      Section {
        Button("Ignore bank transaction", role: .destructive) {
          showingIgnoreConfirmation = true
        }
      } footer: {
        Text("Ignore only if this bank item should not appear in your budget.")
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle("Review")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button {
        confirm()
      } label: {
        Text(primaryTitle)
          .frame(maxWidth: .infinity)
      }
        .bowPrimaryButton()
        .disabled(selected == nil || needsEnvelope)
        .padding(.horizontal, Bow.Space.s4)
        .padding(.bottom, Bow.Space.s2)
    }
    .task(id: record.id) { loadCandidates() }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
      loadCandidates()
    }
    .confirmationDialog("Ignore this bank transaction?", isPresented: $showingIgnoreConfirmation) {
      Button("Ignore transaction", role: .destructive) { resolve(.ignore) }
    } message: {
      Text("It will not appear in Spending or affect your budget.")
    }
    .alert("Couldn’t complete review", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private var primaryTitle: String {
    switch selected {
    case .match: "Confirm match"
    case .addNew:
      if let name = envelopes.first(where: { $0.id == envelopeID })?.name, record.amountMinor < 0 {
        "Add to \(name)"
      } else {
        record.status == .imported ? "Complete review" : "Add transaction"
      }
    case nil: "Choose an option"
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
