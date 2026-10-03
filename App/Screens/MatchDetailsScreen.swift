import SwiftUI

/// The two halves of a match, side by side, with Unmatch at the bottom. Pushed from the
/// transaction sheet's Match details row.
struct MatchDetailsScreen: View {
  @Environment(\.dismiss) private var dismiss
  var entered: Side
  var bank: Side
  /// Explains what Unmatch does in this context.
  var unmatchFootnote: String
  var onUnmatch: () -> Void

  struct Side {
    var payee: String
    var date: Date
    var amountMinor: Int64
    var currencyCode: String
    var isPending = false
  }

  var body: some View {
    Form {
      Section("Entered by you") {
        row(entered, systemImage: "pencil")
      }
      .listRowBackground(Bow.card)
      Section {
        row(bank, systemImage: bank.isPending ? "clock" : "building.columns")
      } header: {
        Text("From your bank")
      } footer: {
        Text("Transactions you enter are matched automatically with bank transactions of the same amount, if they're within 10 days of each other. \(unmatchFootnote)")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle("Match Details")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button(role: .destructive) {
        onUnmatch()
        dismiss()
      } label: {
        Label("Unmatch", systemImage: "personalhotspot.slash")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
      }
      .bowSecondaryButton()
      .foregroundStyle(Bow.overInk)
      .padding(.horizontal, Bow.Space.s4)
      .padding(.bottom, Bow.Space.s2)
    }
  }

  private func row(_ side: Side, systemImage: String) -> some View {
    HStack(spacing: Bow.Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(side.payee.isEmpty ? "Transaction" : side.payee)
          .foregroundStyle(Bow.ink)
        Text(side.date.formatted(date: .abbreviated, time: .omitted))
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: Bow.Space.s2)
      MoneyText(minor: side.amountMinor, currencyCode: side.currencyCode)
        .foregroundStyle(Bow.ink)
      Image(systemName: systemImage)
        .font(.bowFootnote)
        .foregroundStyle(Bow.inkSoft)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}
