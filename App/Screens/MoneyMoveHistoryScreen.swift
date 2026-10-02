import SwiftUI

/// Every move in or out of one envelope or card payment during the month being viewed.
struct MoneyMoveHistoryScreen: View {
  var title: String
  var month: Date
  var entries: [MoneyMoveEntry]
  var currencyCode: String

  private var monthTitle: String { month.formatted(.dateTime.month(.wide).year()) }

  private var days: [(day: Date, entries: [MoneyMoveEntry])] {
    let byDay = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
    return byDay.keys.sorted(by: >).map { ($0, byDay[$0] ?? []) }
  }

  private var netMinor: Int64 { entries.reduce(0) { $0 + $1.signedMinor } }

  var body: some View {
    List {
      if entries.isEmpty {
        Section {
          Text("No money moved in or out in \(monthTitle).")
            .font(.bowBody)
            .foregroundStyle(Bow.inkSoft)
        }
        .listRowBackground(Bow.card)
      } else {
        Section {
          LabeledContent("Net for \(monthTitle)") {
            MoneyText(minor: netMinor, currencyCode: currencyCode, showsPlusSign: true)
              .foregroundStyle(netMinor > 0 ? Bow.fundedInk : Bow.ink)
          }
          .fontWeight(.semibold)
        }
        .listRowBackground(Bow.card)
        ForEach(days, id: \.day) { day in
          Section(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) {
            ForEach(day.entries) { entry in
              MoneyMoveHistoryRow(entry: entry, currencyCode: currencyCode)
            }
          }
          .listRowBackground(Bow.card)
        }
      }
    }
    .bowListBackground()
    .bowSoftScrollEdge()
    .navigationTitle("Money Moves")
    .navigationSubtitle("\(title) · \(monthTitle)")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct MoneyMoveHistoryRow: View {
  var entry: MoneyMoveEntry
  var currencyCode: String

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      Image(systemName: entry.isIn ? "arrow.down" : "arrow.up")
        .font(.bowSubhead.weight(.semibold))
        .foregroundStyle(entry.isIn ? Bow.fundedInk : Bow.inkSoft)
        .frame(width: 28, height: 28)
        .background(Bow.mist, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(.bowHeadline)
          .foregroundStyle(Bow.ink)
          .lineLimit(1)
        Text(entry.isIn ? "Moved in" : "Moved out")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
      }
      Spacer(minLength: Bow.Space.s2)
      MoneyText(minor: entry.signedMinor, currencyCode: currencyCode, showsPlusSign: true)
        .font(.bowAmount)
        .foregroundStyle(entry.isIn ? Bow.fundedInk : Bow.ink)
    }
    .padding(.vertical, Bow.Space.s1)
    .accessibilityElement(children: .combine)
  }
}
