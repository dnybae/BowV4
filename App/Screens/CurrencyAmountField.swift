import SwiftUI
import UIKit

/// A currency input where digits shift in from the right: typing 1, 2, 5 shows $0.01, $0.12, $1.25.
struct CurrencyAmountField: View {
  var title: String
  @Binding var minor: Int64
  var currencyCode: String
  var allowsNegative: Bool = false
  var style: Style = .row
  /// Shows a row's title as an icon-tile label.
  var systemImage: String? = nil
  /// Puts the cursor here as soon as the field is on screen, e.g. a new transaction's amount.
  var focusOnAppear = false

  enum Style {
    /// A form row with the title on the leading side and the amount trailing.
    case row
    /// A large, centered amount that serves as a screen's hero number.
    case hero
    /// The editor sheet's amount hero: the title above a 50pt centered amount.
    case editorHero

    fileprivate var heroSize: CGFloat? {
      switch self {
      case .row: nil
      case .hero: 44
      case .editorHero: 50
      }
    }
  }

  init(_ title: String, minor: Binding<Int64>, currencyCode: String, allowsNegative: Bool = false,
       style: Style = .row, systemImage: String? = nil, focusOnAppear: Bool = false) {
    self.title = title
    _minor = minor
    self.currencyCode = currencyCode
    self.allowsNegative = allowsNegative
    self.style = style
    self.systemImage = systemImage
    self.focusOnAppear = focusOnAppear
  }

  var body: some View {
    switch style {
    case .row:
      LabeledContent {
        field
      } label: {
        BowFieldTitle(title: title, systemImage: systemImage)
      }
    case .hero:
      field
    case .editorHero:
      VStack(spacing: Bow.Space.s1) {
        Text(title)
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .accessibilityHidden(true)
        field
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var field: some View {
    CurrencyTextFieldRepresentable(
      title: title, minor: $minor, currencyCode: currencyCode, allowsNegative: allowsNegative,
      heroSize: style.heroSize, focusOnAppear: focusOnAppear
    )
  }
}

private struct CurrencyTextFieldRepresentable: UIViewRepresentable {
  var title: String
  @Binding var minor: Int64
  var currencyCode: String
  var allowsNegative: Bool
  /// Point size of a hero amount; nil for a form row.
  var heroSize: CGFloat?
  var focusOnAppear = false
  private var isHero: Bool { heroSize != nil }
  @Environment(\.isEnabled) private var isEnabled

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  /// Body-size SF Pro Rounded with tabular digits, scaled for Dynamic Type.
  private static var moneyFont: UIFont { roundedMoneyFont(size: 17, weight: .regular, textStyle: .body) }

  /// Bow's hero number: SF Pro Rounded Semibold (44pt, or 50pt in editor sheets), scaled for Dynamic Type.
  private static func heroFont(size: CGFloat) -> UIFont { roundedMoneyFont(size: size, weight: .semibold, textStyle: .largeTitle) }

  private static func roundedMoneyFont(size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    let descriptor = (base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor)
      .addingAttributes([.featureSettings: [[
        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
      ]]])
    return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont(descriptor: descriptor, size: size))
  }

  func makeUIView(context: Context) -> CurrencyInputTextField {
    let field = CurrencyInputTextField()
    field.delegate = context.coordinator
    field.keyboardType = .numberPad
    field.textAlignment = isHero ? .center : .right
    field.font = heroSize.map(Self.heroFont(size:)) ?? Self.moneyFont
    if isHero {
      field.adjustsFontSizeToFitWidth = true
      field.minimumFontSize = 24
      // The big number itself shows what's being typed; no blinking caret.
      field.tintColor = .clear
    }
    field.adjustsFontForContentSizeCategory = true
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.inputAccessoryView = context.coordinator.makeAccessoryBar(for: field)
    field.focusOnAppear = focusOnAppear
    return field
  }

  func updateUIView(_ field: CurrencyInputTextField, context: Context) {
    context.coordinator.parent = self
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
    /// Lets someone choose a negative sign before typing any digits.
    private var isNegativeZero = false

    init(parent: CurrencyTextFieldRepresentable) { self.parent = parent }

    func render(in field: UITextField) {
      if parent.minor != 0 || !parent.allowsNegative { isNegativeZero = false }
      let formatted = BudgetMoney.formatted(parent.minor, currencyCode: parent.currencyCode)
      let text = isNegativeZero ? "\u{2212}" + formatted : formatted
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

    func textFieldDidBeginEditing(_ textField: UITextField) {
      moveCaretToEnd(textField)
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
      guard let range = textField.selectedTextRange,
            range.start != textField.endOfDocument || !range.isEmpty else { return }
      moveCaretToEnd(textField)
    }

    private func moveCaretToEnd(_ textField: UITextField) {
      let end = textField.endOfDocument
      textField.selectedTextRange = textField.textRange(from: end, to: end)
    }

    /// Only fields that take a negative amount get a bar above the keyboard, holding the sign toggle.
    /// Everywhere else the keyboard sits flush; tapping outside the field or scrolling dismisses it.
    func makeAccessoryBar(for field: UITextField) -> UIToolbar? {
      guard parent.allowsNegative else { return nil }
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
      bar.items = [sign, .flexibleSpace()]
      return bar
    }
  }
}

final class CurrencyInputTextField: UITextField, UIGestureRecognizerDelegate {
  /// Becomes first responder the first time the field lands in a window.
  var focusOnAppear = false
  private var didFocusOnAppear = false
  /// While editing, a tap anywhere outside the field puts the keyboard away.
  private lazy var outsideTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
    tap.cancelsTouchesInView = false
    tap.delegate = self
    return tap
  }()

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard focusOnAppear, !didFocusOnAppear, window != nil else { return }
    // Wait for the actual sheet transition, rather than a timer that could steal focus
    // after the person has already moved to another field or dismissed the keyboard.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.window != nil else { return }
      var responder: UIResponder? = self.next
      while let current = responder {
        if let controller = current as? UIViewController,
           let transition = controller.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { [weak self] context in
             if !context.isCancelled { self?.focusInitially() }
           }) {
          return
        }
        responder = current.next
      }
      self.focusInitially()
    }
  }

  override func becomeFirstResponder() -> Bool {
    let becameFirstResponder = super.becomeFirstResponder()
    if becameFirstResponder {
      didFocusOnAppear = true
      window?.addGestureRecognizer(outsideTap)
    }
    return becameFirstResponder
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { outsideTap.view?.removeGestureRecognizer(outsideTap) }
    return resigned
  }

  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    if newWindow == nil { outsideTap.view?.removeGestureRecognizer(outsideTap) }
  }

  @objc private func handleOutsideTap(_ tap: UITapGestureRecognizer) {
    guard isFirstResponder, !bounds.contains(tap.location(in: self)) else { return }
    _ = resignFirstResponder()
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

  private func focusInitially() {
    guard focusOnAppear, !didFocusOnAppear, window != nil else { return }
    _ = becomeFirstResponder()
  }

  override func closestPosition(to point: CGPoint) -> UITextPosition? { endOfDocument }

  override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

  override func caretRect(for position: UITextPosition) -> CGRect {
    super.caretRect(for: endOfDocument)
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    action == #selector(paste(_:)) && UIPasteboard.general.hasStrings
  }
}
