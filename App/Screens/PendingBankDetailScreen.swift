import SwiftUI
import SwiftData

struct PendingBankDetailScreen: View {
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
        LabeledContent("Amount") {
          Text(BudgetMoney.formatted(
            record.amountMinor, currencyCode: account?.currencyCode ?? "USD"
          ))
            .fontDesign(.rounded).monospacedDigit()
        }
        LabeledContent("Date", value: record.date.formatted(date: .abbreviated, time: .omitted))
        LabeledContent("Account", value: account?.name ?? "Account")
      } header: {
        Text("Pending at bank")
      } footer: {
        Text("The final posted amount and date may differ. Bow will check for a match when it posts.")
      }
      .listRowBackground(Bow.card)

      if let transactionID = record.transactionID {
        Section {
          Button("View Entered Transaction", systemImage: "arrow.up.right") {
            onSelectTransaction(transactionID)
          }
        } footer: {
          Text("Your entered transaction already affects your budget. The bank authorization does not add a second transaction.")
        }
        .listRowBackground(Bow.card)
      } else {
        Section {
          if record.amountMinor < 0 {
            CategorySelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Choose an Envelope"
            )
          }
        } footer: {
          Text("Record Now creates a manual transaction and affects your budget immediately. Choose an envelope for an expense.")
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
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
          Text("Record Now")
            .frame(maxWidth: .infinity)
        }
        .bowPrimaryButton()
        .disabled(record.amountMinor < 0 && envelopeID == nil)
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
