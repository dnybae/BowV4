import SwiftUI
import SwiftData

struct SimpleFINReviewScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var accounts: [BudgetAccount]
  var record: SimpleFINImportRecord
  var relatedOccurrence: BudgetScheduleOccurrence? = nil
  var relatedSchedule: BudgetSchedule? = nil
  var onRecordScheduledTransfer: ((ScheduledTransactionDraft) -> Void)? = nil
  @State private var selectedID: UUID?
  @State private var message: String?
  @State private var candidates: [BudgetTransaction] = []

  private var account: BudgetAccount? { accounts.first { $0.id == record.localAccountID } }
  var body: some View {
    Form {
      Section("Bank Transaction") {
        LabeledContent("Payee", value: record.payee)
        LabeledContent("Amount", value: BudgetMoney.formatted(record.amountMinor, currencyCode: account?.currencyCode ?? "USD"))
        LabeledContent("Date", value: record.date.formatted(date: .abbreviated, time: .omitted))
        if let account { LabeledContent("Account", value: account.name) }
      }

      Section {
        if candidates.isEmpty {
          Text("No likely Bow transaction was found. You can import this bank transaction or ignore it.")
            .foregroundStyle(.secondary)
        }
        ForEach(candidates) { candidate in
          Button {
            selectedID = candidate.id
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(candidate.payee.isEmpty ? "Transfer" : candidate.payee)
                  .foregroundStyle(.primary)
                Text(candidate.date.formatted(date: .abbreviated, time: .omitted))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(BudgetMoney.formatted(
                candidate.transferAccountID == record.localAccountID
                  ? -candidate.amountMinor : candidate.amountMinor,
                currencyCode: account?.currencyCode ?? "USD"
              ))
                .foregroundStyle(.primary)
              if selectedID == candidate.id {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
                  .accessibilityHidden(true)
              }
            }
          }
          .accessibilityAddTraits(selectedID == candidate.id ? .isSelected : [])
        }
      } header: {
        Text("Possible Matches")
      } footer: {
        Text("Linking keeps your existing payee, date, notes, and category. If the amount changed, Bow uses the bank amount. The result will need approval.")
      }

      Section {
        if relatedSchedule?.kind == .transfer {
          Text("This bank entry belongs to a scheduled transfer. Record the transfer, then link this bank entry to it.")
            .font(.footnote).foregroundStyle(.secondary)
          if let relatedOccurrence, let relatedSchedule {
            Button("Record Scheduled Transfer", systemImage: "arrow.left.arrow.right") {
              onRecordScheduledTransfer?(ScheduledTransactionDraft(
                scheduleID: relatedSchedule.id, scheduledFor: relatedOccurrence.scheduledFor,
                accountID: relatedSchedule.accountID,
                transferAccountID: relatedSchedule.transferAccountID,
                envelopeID: relatedSchedule.envelopeID, kind: .transfer,
                amountMinor: relatedSchedule.amountMinor, payee: relatedSchedule.payee,
                notes: relatedSchedule.notes, date: relatedOccurrence.scheduledFor
              ))
            }
          }
        }
        Button("Link Selected Transaction", systemImage: "link") {
          guard let selectedID else { return }
          resolve(.link(selectedID))
        }
        .disabled(selectedID == nil)
        if relatedSchedule?.kind != .transfer {
          Button("Import as New Transaction", systemImage: "plus") {
            resolve(.importNew)
          }
        }
        Button("Ignore Bank Transaction", role: .destructive) {
          resolve(.ignore)
        }
      }
    }
    .navigationTitle("Review Match")
    .task(id: record.id) {
      do {
        let nearby = try BudgetTransactionLookup.near(
          accountID: record.localAccountID, date: record.date, days: 10, in: modelContext
        )
        let matches = try nearby.filter { transaction in
          let id = transaction.id
          let accountID = record.localAccountID
          let ignored = SimpleFINImportStatus.ignored.rawValue
          let other = FetchDescriptor<SimpleFINImportRecord>(predicate: #Predicate {
            $0.transactionID == id && $0.localAccountID == accountID
              && $0.statusRaw != ignored
          })
          let used = try modelContext.fetch(other).contains { $0.id != record.id }
          return !used && SimpleFINSyncCoordinator.isPossibleMatch(transaction, for: record)
        }
        candidates = (relatedSchedule?.kind == .transfer
          ? matches.filter { $0.kind == .transfer } : matches)
          .sorted { abs($0.date.timeIntervalSince(record.date)) < abs($1.date.timeIntervalSince(record.date)) }
      } catch {
        message = error.localizedDescription
      }
    }
    .alert("Could Not Resolve Match", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func resolve(_ decision: SimpleFINReviewDecision) {
    do {
      try SimpleFINSyncCoordinator.shared.resolve(
        record, as: decision,
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
