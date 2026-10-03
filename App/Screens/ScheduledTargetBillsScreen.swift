import SwiftUI

/// The scheduled bills that add to an envelope's target in the month being viewed.
struct ScheduledTargetBillsScreen: View {
  var envelopeName: String
  var month: Date
  var contributions: [ScheduleTargetContribution]
  var schedules: [BudgetSchedule]
  var currencyCode: String
  var isPastMonth: Bool
  var onEditSchedule: (UUID) -> Void

  private var monthName: String { month.formatted(.dateTime.month(.wide)) }
  private var totalMinor: Int64 { contributions.reduce(0) { $0 + $1.totalMinor } }

  var body: some View {
    List {
      Section {
        ForEach(contributions) { contribution in
          let row = TransactionRowView(model: rowModel(for: contribution), currencyCode: currencyCode,
                                       options: .hidesEnvelope)
          if isPastMonth {
            row
          } else {
            Button { onEditSchedule(contribution.scheduleID) } label: { row }
          }
        }
      } footer: {
        Text("Each bill adds what’s due in \(monthName) to \(envelopeName)’s target automatically. Edit or pause a bill to change it.")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)

      Section {
        EnvelopeDetailValueRow(title: "Total for \(monthName)", isEmphasized: true) {
          MoneyText(minor: totalMinor, currencyCode: currencyCode)
        }
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .bowSoftScrollEdge()
    .navigationTitle("Scheduled Bills")
    .navigationSubtitle("\(envelopeName) · \(month.formatted(.dateTime.month(.wide).year()))")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func rowModel(for contribution: ScheduleTargetContribution) -> TransactionRowModel {
    let schedule = schedules.first { $0.id == contribution.scheduleID }
    let frequency = schedule?.frequency ?? .monthly
    let when = switch (frequency, contribution.occurrences) {
    case (.once, _): "One-time"
    case (_, 1): frequency.title
    default: "\(frequency.title) · \(contribution.occurrences) this month"
    }
    return TransactionRowModel(
      id: contribution.scheduleID.uuidString,
      title: TransactionRowModel.title(payee: contribution.payee, kind: schedule?.kind ?? .expense),
      logoName: contribution.payee,
      merchantDomain: nil,
      kind: schedule?.kind ?? .expense,
      accountName: "",
      envelopeName: envelopeName,
      amountMinor: -contribution.totalMinor,
      state: .scheduled(when)
    )
  }
}
