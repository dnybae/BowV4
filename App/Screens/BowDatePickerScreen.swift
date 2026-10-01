import SwiftUI

/// Where an editor's Date row pushes: a full calendar for picking the date.
struct BowDatePickerScreen: View {
  var title: String
  @Binding var date: Date
  var range: ClosedRange<Date> = Date.distantPast...Date.distantFuture

  var body: some View {
    Form {
      DatePicker(title, selection: $date, in: range, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
