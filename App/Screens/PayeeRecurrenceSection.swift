import SwiftUI

/// Suggests a schedule for a detected recurring charge, or flags a schedule whose amount is out of date.
struct PayeeRecurrenceSection: View {
  var recurrence: PayeeRecurrence
  /// The payee's active expense schedule, when there is exactly one.
  var existingSchedule: BudgetSchedule?
  var hasOtherSchedules: Bool
  var currencyCode: String
  var onCreateSchedule: () -> Void
  var onEditSchedule: (BudgetSchedule) -> Void

  private func money(_ minor: Int64) -> String {
    BudgetMoney.formatted(minor, currencyCode: currencyCode)
  }

  var body: some View {
    if let existingSchedule {
      if existingSchedule.amountMinor != recurrence.amountMinor {
        Section {
          Label {
            Text("Your schedule expects \(money(existingSchedule.amountMinor)), but recent charges are \(money(recurrence.amountMinor)).")
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(Bow.needs)
          }
          Button("Update schedule", systemImage: "calendar") {
            onEditSchedule(existingSchedule)
          }
        } header: {
          Text("Price change")
        } footer: {
          Text("Updating the amount keeps the envelope’s monthly target accurate.")
        }
        .listRowBackground(Bow.card)
      }
    } else if !hasOtherSchedules {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(recurrence.frequency.title) · about \(money(recurrence.amountMinor))")
            .font(.bowHeadline)
            .foregroundStyle(Bow.ink)
          Text("Next around \(recurrence.nextDate.formatted(.dateTime.month(.abbreviated).day()))")
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
          if let previous = recurrence.previousAmountMinor {
            Label("Up from \(money(previous))", systemImage: "arrow.up.right")
              .font(.bowSubhead)
              .foregroundStyle(Bow.needsInk)
          }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        Button("Create schedule", systemImage: "calendar.badge.plus", action: onCreateSchedule)
      } header: {
        Text("Looks recurring")
      } footer: {
        Text("A schedule shows this bill on your calendar and adds it to its envelope’s monthly target.")
      }
      .listRowBackground(Bow.card)
    }
  }
}
