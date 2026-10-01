import SwiftUI
import SwiftData

struct AddAccountFlowScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var connections: [SimpleFINConnection]
  var currencyCode: String
  var isDemoMode: Bool
  @State private var path: [AccountSetupRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          Text("How do you want to track it?")
            .font(.bowLargeTitle)
            .foregroundStyle(Bow.ink)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Bow.Space.s4, leading: Bow.Space.s1, bottom: 0, trailing: Bow.Space.s1))
        }

        Section {
          NavigationLink(value: AccountSetupRoute.bank) {
            optionRow(
              title: "Connect a bank",
              detail: connections.isEmpty
                ? "Sync balances and transactions through SimpleFIN. You review each one before it counts."
                : "View your SimpleFIN accounts and choose any new ones to add.",
              note: isDemoMode
                ? "Explore a sample bank connection. Demo mode never contacts a bank."
                : "SimpleFIN is read-only and has a separate signup and fee. Updates arrive about once a day.",
              symbol: "link"
            )
          }
        }
        .listRowBackground(Bow.card)

        Section {
          NavigationLink(value: AccountSetupRoute.manual) {
            optionRow(
              title: "Track it yourself",
              detail: "Enter a balance and add transactions by hand, or import a bank file.",
              note: "Works with any bank. Stays on this iPhone.",
              symbol: "pencil"
            )
          }
        }
        .listRowBackground(Bow.card)
      }
      .bowListBackground()
      .navigationTitle("Add account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if path.isEmpty {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
          }
        }
      }
      .navigationDestination(for: AccountSetupRoute.self) { route in
        switch route {
        case .bank:
          SimpleFINAccountSetupScreen(isDemoMode: isDemoMode, onDone: { dismiss() })
        case .manual:
          AccountEditorScreen(currencyCode: currencyCode) { _ in dismiss() }
        }
      }
    }
  }

  private func optionRow(title: String, detail: String, note: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: Bow.Space.s4) {
      Image(systemName: symbol)
        .bowScaledIcon(frame: 44, glyph: 18, weight: .medium)
        .foregroundStyle(Bow.bowInk)
        .background(Bow.bowTint, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        Text(title)
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
        Text(detail)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
        Text(note)
          .font(.bowFootnote)
          .foregroundStyle(Bow.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, Bow.Space.s3)
    .accessibilityElement(children: .combine)
  }
}

private enum AccountSetupRoute: Hashable {
  case bank, manual
}
