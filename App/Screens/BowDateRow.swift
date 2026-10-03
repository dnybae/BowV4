import SwiftUI

/// An editor's Date row: the title on the leading side and a compact date button that opens
/// a calendar popover in place.
struct BowDateRow: View {
  var title: String
  var systemImage: String?
  @Binding var date: Date
  var range: ClosedRange<Date> = Date.distantPast...Date.distantFuture

  var body: some View {
    DatePicker(selection: $date, in: range, displayedComponents: .date) {
      BowFieldTitle(title: title, systemImage: systemImage)
    }
    .datePickerStyle(.compact)
  }
}
