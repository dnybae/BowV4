import SwiftUI

/// A detail screen's summary row: a title with an optional line under it, the value trailing.
/// No icon, so every row in a section lines up the same way.
struct EnvelopeDetailValueRow<Value: View>: View {
  var title: String
  var detail: String?
  var isEmphasized = false
  @ViewBuilder var value: () -> Value

  var body: some View {
    HStack(spacing: Bow.Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.bowHeadline)
          .fontWeight(isEmphasized ? .semibold : nil)
          .foregroundStyle(Bow.ink)
        if let detail {
          Text(detail)
            .font(.bowSubhead)
            .foregroundStyle(Bow.inkSoft)
            .monospacedDigit()
        }
      }
      Spacer(minLength: Bow.Space.s2)
      value()
        .font(.bowAmount)
        .fontWeight(isEmphasized ? .semibold : nil)
        .foregroundStyle(isEmphasized ? Bow.ink : Bow.inkSoft)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

extension EnvelopeDetailValueRow where Value == Text {
  init(title: String, detail: String? = nil, value: String) {
    self.init(title: title, detail: detail) { Text(value) }
  }
}
