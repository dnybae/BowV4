import SwiftUI
import SwiftData

struct AddAccountFlowScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var connections: [SimpleFINConnection]
  var currencyCode: String
  var isDemoMode: Bool
  /// A hand-tracked account was created; the bank route reports nothing because it imports.
  var onCreated: ((BudgetAccount) -> Void)? = nil
  @State private var path: [AccountSetupRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          NavigationLink(value: AccountSetupRoute.bank) {
            optionCard(
              title: connections.isEmpty ? "Connect a bank" : "Add more from your bank",
              summary: connections.isEmpty
                ? "Bring in transactions automatically."
                : "Choose new accounts from your SimpleFIN connection.",
              symbol: "link",
              points: bankPoints,
              actionTitle: connections.isEmpty ? "Set up SimpleFIN" : "View bank accounts"
            )
          }
        }
        .listRowBackground(Bow.card)

        Section {
          NavigationLink(value: AccountSetupRoute.manual) {
            optionCard(
              title: "Track it yourself",
              summary: "Enter a balance and add transactions yourself.",
              symbol: "pencil",
              points: [
                .benefit("Free, and works with any bank"),
                .benefit("Your data stays on this iPhone"),
                .benefit("Import bank files anytime"),
                .tradeoff("You add transactions yourself")
              ],
              actionTitle: "Create account"
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
            Button { dismiss() } label: { BowToolbarLabel("Cancel") }
          }
        }
      }
      .navigationDestination(for: AccountSetupRoute.self) { route in
        switch route {
        case .bank:
          SimpleFINAccountSetupScreen(isDemoMode: isDemoMode, onDone: { dismiss() })
        case .manual:
          AccountEditorScreen(currencyCode: currencyCode, isInFlow: true, onSaved: { account in
            onCreated?(account)
            dismiss()
          })
        }
      }
    }
  }

  private var bankPoints: [OptionPoint] {
    if isDemoMode {
      return [
        .benefit("Explore sample bank accounts"),
        .benefit("Try approving imported transactions"),
        .tradeoff("Demo mode never contacts a bank")
      ]
    }
    if !connections.isEmpty {
      return [
        .benefit("Uses your existing connection"),
        .benefit("New transactions arrive on their own")
      ]
    }
    return [
      .benefit("New transactions arrive on their own"),
      .benefit("Read-only; your bank login stays with SimpleFIN"),
      .benefit("You approve each one before it counts"),
      .tradeoff("Separate SimpleFIN signup and small yearly fee"),
      .tradeoff("Updates about once a day")
    ]
  }

  private func optionCard(title: String, summary: String, symbol: String,
                          points: [OptionPoint], actionTitle: String) -> some View {
    VStack(alignment: .leading, spacing: Bow.Space.s3) {
      BowTileIcon(systemImage: symbol)
      VStack(alignment: .leading, spacing: Bow.Space.s1) {
        Text(title)
          .font(.bowTitle)
          .foregroundStyle(Bow.ink)
        Text(summary)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(alignment: .leading, spacing: Bow.Space.s2) {
        ForEach(points, id: \.text) { point in
          Label {
            Text(point.text)
              .foregroundStyle(Bow.ink)
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: point.isBenefit ? "checkmark.circle" : "exclamationmark.circle")
              .foregroundStyle(point.isBenefit ? Bow.funded : Bow.needs)
          }
          .font(.bowSubhead)
          .accessibilityLabel("\(point.isBenefit ? "Benefit" : "Note"): \(point.text)")
        }
      }
      Text(actionTitle)
        .font(.bowSubhead.weight(.semibold))
        .foregroundStyle(Bow.bowInk)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Bow.Space.s2)
    .accessibilityElement(children: .combine)
  }
}

private struct OptionPoint {
  var text: String
  var isBenefit: Bool

  static func benefit(_ text: String) -> OptionPoint { OptionPoint(text: text, isBenefit: true) }
  static func tradeoff(_ text: String) -> OptionPoint { OptionPoint(text: text, isBenefit: false) }
}

private enum AccountSetupRoute: Hashable {
  case bank, manual
}
