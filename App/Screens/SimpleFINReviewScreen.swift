import SwiftUI
import SwiftData

struct SimpleFINReviewScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var transactions: [BudgetTransaction]
  @Query private var records: [SimpleFINImportRecord]
  @Query private var accounts: [BudgetAccount]
  var record: SimpleFINImportRecord
  @State private var selectedID: UUID?
  @State private var message: String?

  private var account: BudgetAccount? { accounts.first { $0.id == record.localAccountID } }
  private var candidates: [BudgetTransaction] {
    SimpleFINSyncCoordinator.shared.possibleMatches(for: record, among: transactions, records: records)
  }

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
        Button("Link Selected Transaction", systemImage: "link") {
          guard let selectedID else { return }
          resolve(.link(selectedID))
        }
        .disabled(selectedID == nil)
        Button("Import as New Transaction", systemImage: "plus") {
          resolve(.importNew)
        }
        Button("Ignore Bank Transaction", role: .destructive) {
          resolve(.ignore)
        }
      }
    }
    .navigationTitle("Review Match")
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
      try SimpleFINSyncCoordinator.shared.resolve(record, as: decision, in: modelContext)
      dismiss()
    } catch {
      message = error.localizedDescription
    }
  }
}
