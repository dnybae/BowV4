import SwiftUI

struct SelectionRow: View {
  var title: String
  var balance: String?
  var isSelected: Bool
  var symbol: String? = nil

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark")
        .font(.body.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 20)
        .opacity(isSelected ? 1 : 0)
        .accessibilityHidden(true)
      if let symbol {
        Image(systemName: symbol)
          .foregroundStyle(.tint)
          .frame(width: 24)
          .accessibilityHidden(true)
      }
      Text(title)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let balance {
        Text(balance)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityValue(isSelected ? "Selected" : "")
  }
}
