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
        HStack(spacing: Bow.Space.s3) {
          MerchantLogoView(
            merchantName: record.payee,
            kind: record.amountMinor < 0 ? .expense : .inflow
          )
          VStack(alignment: .leading, spacing: 2) {
            Text(record.payee.isEmpty ? "Bank item" : record.payee)
              .font(.bowHeadline)
              .foregroundStyle(Bow.ink)
            Text("\(account?.name ?? "Account") · \(record.date.formatted(date: .abbreviated, time: .omitted))")
              .font(.bowFootnote)
              .foregroundStyle(Bow.inkSoft)
          }
          Spacer(minLength: Bow.Space.s2)
          MoneyText(minor: record.amountMinor, currencyCode: account?.currencyCode ?? "USD")
            .font(.bowTitle)
            .monospacedDigit()
            .foregroundStyle(Bow.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, Bow.Space.s2)
        .accessibilityElement(children: .combine)
      } header: {
        Text("Pending at bank")
      } footer: {
        Text("The final posted amount and date may differ. Bow will check for a match when it posts.")
      }
      .listRowBackground(Bow.card)

      if let transactionID = record.transactionID {
        Section {
          Button("View entered transaction", systemImage: "arrow.up.right") {
            onSelectTransaction(transactionID)
          }
        } footer: {
          Text("Your entered transaction already affects your budget. The bank authorization does not add a second transaction.")
        }
        .listRowBackground(Bow.card)
      } else {
        Section {
          if record.amountMinor < 0 {
            EnvelopeSelectionField(
              title: "Envelope", selection: $envelopeID,
              envelopes: envelopes, noneTitle: "Choose an envelope"
            )
          }
        } footer: {
          Text("Record now creates a manual transaction and affects your budget immediately. Choose an envelope for an expense.")
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
    .navigationTitle("Pending at bank")
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
          Text("Record now")
            .frame(maxWidth: .infinity)
        }
        .bowPrimaryButton()
        .disabled(record.amountMinor < 0 && envelopeID == nil)
        .padding(.horizontal, Bow.Space.s4)
        .padding(.bottom, Bow.Space.s2)
      }
    }
    .alert("Couldn’t enter transaction", isPresented: Binding(
      get: { message != nil }, set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }
}
