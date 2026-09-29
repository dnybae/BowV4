import SwiftUI
import SwiftData

struct AddAccountFlowScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var connections: [SimpleFINConnection]
  var currencyCode: String
  var isDemoMode: Bool

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Choose how you want to track this account.")
            .foregroundStyle(.secondary)
        }

        Section {
          NavigationLink {
            AccountEditorScreen(currencyCode: currencyCode) { _ in dismiss() }
          } label: {
            optionRow(
              title: "Private Account",
              detail: "Enter balances and transactions yourself, or import a bank file later.",
              symbol: "wallet.pass"
            )
          }
        } footer: {
          Text("Works with any bank. Your account details stay in Bow on this iPhone.")
        }

        Section {
          NavigationLink {
            SimpleFINAccountSetupScreen(isDemoMode: isDemoMode, onDone: { dismiss() })
          } label: {
            optionRow(
              title: "Connect a Bank",
              detail: connections.isEmpty
                ? "Enter a SimpleFIN setup token, then choose which bank accounts to add."
                : "View your SimpleFIN accounts and choose any new ones to add.",
              symbol: "link"
            )
          }
        } footer: {
          Text(isDemoMode
            ? "Explore a sample bank connection. Demo mode never contacts a bank."
            : "SimpleFIN provides read-only bank data and has a separate signup and fee. Bank updates may arrive about once a day.")
        }
      }
      .navigationTitle("Add Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func optionRow(title: String, detail: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
    }
    .accessibilityElement(children: .combine)
  }
}
