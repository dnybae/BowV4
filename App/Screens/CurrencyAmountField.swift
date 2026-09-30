import SwiftUI
import UIKit

/// A currency input where digits shift in from the right: typing 1, 2, 5 shows $0.01, $0.12, $1.25.
struct CurrencyAmountField: View {
  var title: String
  @Binding var minor: Int64
  var currencyCode: String
  var allowsNegative: Bool = false

  init(_ title: String, minor: Binding<Int64>, currencyCode: String, allowsNegative: Bool = false) {
    self.title = title
    _minor = minor
    self.currencyCode = currencyCode
    self.allowsNegative = allowsNegative
  }

  var body: some View {
    LabeledContent(title) {
      CurrencyTextFieldRepresentable(
        title: title, minor: $minor, currencyCode: currencyCode, allowsNegative: allowsNegative
      )
    }
  }
}

private struct CurrencyTextFieldRepresentable: UIViewRepresentable {
  var title: String
  @Binding var minor: Int64
  var currencyCode: String
  var allowsNegative: Bool
  @Environment(\.isEnabled) private var isEnabled

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  /// Body-size SF Pro Rounded with tabular digits, scaled for Dynamic Type.
  private static var moneyFont: UIFont {
    let body = UIFont.systemFont(ofSize: 17)
    let descriptor = (body.fontDescriptor.withDesign(.rounded) ?? body.fontDescriptor)
      .addingAttributes([.featureSettings: [[
        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
      ]]])
    return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(descriptor: descriptor, size: 17))
  }

  func makeUIView(context: Context) -> CurrencyInputTextField {
    let field = CurrencyInputTextField()
    field.delegate = context.coordinator
    field.keyboardType = .numberPad
    field.textAlignment = .right
    field.font = Self.moneyFont
    field.adjustsFontForContentSizeCategory = true
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.inputAccessoryView = context.coordinator.makeAccessoryBar(for: field)
    return field
  }

  func updateUIView(_ field: CurrencyInputTextField, context: Context) {
    context.coordinator.parent = self
    context.coordinator.refreshAccessoryBar()
    field.accessibilityLabel = title
    field.isEnabled = isEnabled
    context.coordinator.render(in: field)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: CurrencyInputTextField, context: Context) -> CGSize? {
    let height = uiView.intrinsicContentSize.height
    return CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: height)
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: CurrencyTextFieldRepresentable
    private var signButton: UIBarButtonItem?
    private weak var accessoryBar: UIToolbar?
    /// Lets someone choose a negative sign before typing any digits.
    private var isNegativeZero = false

    init(parent: CurrencyTextFieldRepresentable) { self.parent = parent }

    func render(in field: UITextField) {
      if parent.minor != 0 || !parent.allowsNegative { isNegativeZero = false }
      let formatted = BudgetMoney.formatted(parent.minor, currencyCode: parent.currencyCode)
      let text = isNegativeZero ? "-" + formatted : formatted
      if field.text != text { field.text = text }
      field.textColor = parent.minor == 0 ? UIColor(Bow.inkSoft) : UIColor(Bow.ink)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
      let current = parent.minor
      let updated: Int64
      if string.isEmpty {
        updated = CurrencyInputEditor.deletingLastDigit(from: current)
        if current < 0 && updated == 0 { isNegativeZero = true }
      } else if string.count > 1 {
        updated = CurrencyInputEditor.pasted(string, into: current, allowsNegative: parent.allowsNegative)
      } else {
        let appended = CurrencyInputEditor.appending(string, to: current)
        updated = isNegativeZero ? -appended : appended
      }
      if updated != current { parent.minor = updated }
      render(in: textField)
      moveCaretToEnd(textField)
      return false
    }

    func textFieldDidBeginEditing(_ textField: UITextField) { moveCaretToEnd(textField) }

    func textFieldDidChangeSelection(_ textField: UITextField) {
      guard let range = textField.selectedTextRange,
            range.start != textField.endOfDocument || !range.isEmpty else { return }
      moveCaretToEnd(textField)
    }

    private func moveCaretToEnd(_ textField: UITextField) {
      let end = textField.endOfDocument
      textField.selectedTextRange = textField.textRange(from: end, to: end)
    }

    func makeAccessoryBar(for field: UITextField) -> UIToolbar {
      let bar = UIToolbar()
      bar.sizeToFit()
      let sign = UIBarButtonItem(title: "+/−", primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        if self.parent.minor == 0 {
          self.isNegativeZero.toggle()
        } else {
          self.parent.minor = -self.parent.minor
        }
        self.render(in: field)
      })
      sign.accessibilityLabel = "Toggle Negative"
      let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak field] _ in
        field?.resignFirstResponder()
      })
      signButton = sign
      accessoryBar = bar
      refreshAccessoryBar(done: done)
      return bar
    }

    func refreshAccessoryBar(done: UIBarButtonItem? = nil) {
      guard let bar = accessoryBar, let signButton else { return }
      let doneItem = done ?? bar.items?.last ?? UIBarButtonItem(systemItem: .done)
      let items = parent.allowsNegative
        ? [signButton, .flexibleSpace(), doneItem]
        : [.flexibleSpace(), doneItem]
      if bar.items != items { bar.items = items }
    }
  }
}

final class CurrencyInputTextField: UITextField {
  override func closestPosition(to point: CGPoint) -> UITextPosition? { endOfDocument }

  override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

  override func caretRect(for position: UITextPosition) -> CGRect {
    super.caretRect(for: endOfDocument)
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    action == #selector(paste(_:)) && UIPasteboard.general.hasStrings
  }
}
