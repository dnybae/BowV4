import SwiftUI
import UIKit

/// Bridges UIKit's attempted-dismiss callback, which SwiftUI's dismiss-disabled modifier
/// doesn't expose. The original presentation delegate continues to receive its other callbacks.
struct EditorDismissGuard: UIViewControllerRepresentable {
  var hasChanges: Bool
  var onAttempt: () -> Void

  func makeUIViewController(context: Context) -> ObserverController {
    ObserverController()
  }

  func updateUIViewController(_ controller: ObserverController, context: Context) {
    controller.guardDelegate.hasChanges = hasChanges
    controller.guardDelegate.onAttempt = onAttempt
    controller.install()
    // The representable can update before SwiftUI attaches the sheet's hosting controller.
    DispatchQueue.main.async { [weak controller] in controller?.install() }
  }

  static func dismantleUIViewController(_ controller: ObserverController, coordinator: ()) {
    controller.uninstall()
  }

  final class ObserverController: UIViewController {
    let guardDelegate = DismissDelegate()
    weak var observedPresentation: UIPresentationController?

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      install()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      install()
    }

    func install() {
      var host: UIViewController? = self
      while let current = host {
        if let presenter = current.presentingViewController,
           presenter.presentedViewController === current,
           let presentation = current.presentationController {
          if presentation.delegate !== guardDelegate {
            uninstall()
            guardDelegate.original = presentation.delegate
            observedPresentation = presentation
            presentation.delegate = guardDelegate
          }
          return
        }
        host = current.parent
      }
    }

    func uninstall() {
      if let presentation = observedPresentation, presentation.delegate === guardDelegate {
        presentation.delegate = guardDelegate.original
      }
      observedPresentation = nil
    }
  }

  final class DismissDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
    var hasChanges = false
    var onAttempt: (() -> Void)?
    weak var original: (any UIAdaptivePresentationControllerDelegate)?

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
      !hasChanges && (original?.presentationControllerShouldDismiss?(presentationController) ?? true)
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
      if hasChanges { onAttempt?() }
      else { original?.presentationControllerDidAttemptToDismiss?(presentationController) }
    }

    override func responds(to selector: Selector!) -> Bool {
      super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
      original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
  }
}
