import SwiftUI
import SwiftData

struct PendingBankDetailScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
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
        BowIdentityHeader(
          name: record.payee.isEmpty ? "Bank item" : record.payee,
          context: [account?.name, record.date.formatted(.dateTime.month(.abbreviated).day())]
            .compactMap { $0 }.joined(separator: ", "),
          amountMinor: record.amountMinor,
          currencyCode: account?.currencyCode ?? "USD",
          pill: .pendingAtBank
        ) {
          MerchantLogoView(
            merchantName: record.payee,
            kind: record.amountMinor < 0 ? .expense : .inflow,
            size: 64, style: .glossy
          )
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

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
              envelopes: envelopes, noneTitle: "Choose an envelope", systemImage: "square.grid.2x2"
            )
          }
        } footer: {
          Text("The final posted amount and date may differ. Bow will check for a match when it posts. Record now adds it to your budget right away.")
        }
        .listRowBackground(Bow.card)
      }

      if !record.payee.isEmpty {
        Section {
          NavigationLink {
            PayeeDetailScreen(payeeKey: PayeeDirectory.canonicalKey(for: record.payee, payees: payees))
          } label: {
            LabeledContent {
              Text(record.payee)
            } label: {
              Label("Payee", systemImage: "person").labelStyle(.bowTile)
            }
          }
          .accessibilityHint("Opens payee details")
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowSkyList(mood: .dawn, height: 420)
    .navigationTitle("Pending")
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
