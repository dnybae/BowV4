import SwiftUI
import SwiftData

struct PendingBankScreen: View {
  var records: [SimpleFINImportRecord]
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var onSelectTransaction: (UUID) -> Void

  private var pending: [SimpleFINImportRecord] {
    records.filter { $0.bankState == .pending && $0.isVisiblePending }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    List {
      Section {
        Text("These bank authorizations may change or disappear before they post. They do not affect your budget unless you choose Enter Now.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      if pending.isEmpty {
        ContentUnavailableView(
          "No Pending Bank Items", systemImage: "clock",
          description: Text("Pending authorizations will appear here after your next bank sync.")
        )
      } else {
        Section("Pending at bank") {
          ForEach(pending) { record in
            NavigationLink {
              PendingBankDetailScreen(
                record: record, accounts: accounts, envelopes: envelopes,
                onSelectTransaction: onSelectTransaction
              )
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "clock")
                  .foregroundStyle(.orange)
                  .frame(width: 32)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(record.payee.isEmpty ? "Bank item" : record.payee)
                  Text("\(accounts.first { $0.id == record.localAccountID }?.name ?? "Account") · \(record.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                  if record.transactionID != nil {
                    Text("Entered in budget")
                      .font(.caption).foregroundStyle(.tint)
                  }
                }
                Spacer(minLength: 8)
                Text(BudgetMoney.formatted(
                  record.amountMinor,
                  currencyCode: accounts.first { $0.id == record.localAccountID }?.currencyCode ?? "USD"
                ))
              }
            }
          }
        }
      }
    }
    .navigationTitle("Pending at Bank")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PendingBankDetailScreen: View {
  @Environment(\.modelContext) private var modelContext
  var record: SimpleFINImportRecord
  var accounts: [BudgetAccount]
  var envelopes: [BudgetEnvelope]
  var onSelectTransaction: (UUID) -> Void
  @State private var envelopeID: UUID?
  @State private var message: String?

  private var account: BudgetAccount? { accounts.first { $0.id == record.localAccountID } }

  var body: some View {
    Form {
      Section {
        LabeledContent("Merchant", value: record.payee)
        LabeledContent("Amount", value: BudgetMoney.formatted(
          record.amountMinor, currencyCode: account?.currencyCode ?? "USD"
        ))
        LabeledContent("Date", value: record.date.formatted(date: .abbreviated, time: .omitted))
        LabeledContent("Account", value: account?.name ?? "Account")
      } header: {
        Text("Pending at bank")
      } footer: {
        Text("The final posted amount and date may differ. Bow will check for a match when it posts.")
      }

      if let transactionID = record.transactionID {
        Section {
          Button("View Entered Transaction", systemImage: "arrow.up.right") {
            onSelectTransaction(transactionID)
          }
        } footer: {
          Text("Your entered transaction already affects your budget. The bank authorization does not add a second transaction.")
        }
      } else {
        Section {
          if record.amountMinor < 0 {
            CategorySelectionField(
              title: "Category", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Needs Categorization"
            )
          }
        } footer: {
          Text("Enter Now creates a manual transaction and affects your budget immediately.")
        }
      }
    }
    .navigationTitle("Pending Bank Item")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if record.transactionID == nil {
        Button {
          do {
            try SimpleFINSyncCoordinator.shared.enterPending(
              record, envelopeID: envelopeID, in: modelContext
            )
          } catch {
            message = error.localizedDescription
          }
        } label: {
          Text("Enter Now")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
      }
    }
    .alert("Could Not Enter Transaction", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }
}
