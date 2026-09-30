import SwiftUI
import UIKit

/// Stops the tab bar from switching to an action-only tab (such as "Add Transaction")
/// and runs an action instead, so its empty page is never shown.
/// Place inside one of the TabView's tabs; it attaches to the enclosing UITabBarController.
struct AddTabInterceptor: UIViewControllerRepresentable {
  var tabTitle: String
  var action: () -> Void

  func makeUIViewController(context: Context) -> AttachingViewController {
    AttachingViewController(interceptor: context.coordinator)
  }

  func updateUIViewController(_ controller: AttachingViewController, context: Context) {
    context.coordinator.tabTitle = tabTitle
    context.coordinator.action = action
    controller.attach()
  }

  func makeCoordinator() -> TabSelectionInterceptor {
    TabSelectionInterceptor(tabTitle: tabTitle, action: action)
  }

  final class AttachingViewController: UIViewController {
    private let interceptor: TabSelectionInterceptor

    init(interceptor: TabSelectionInterceptor) {
      self.interceptor = interceptor
      super.init(nibName: nil, bundle: nil)
      view.isUserInteractionEnabled = false
      view.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      attach()
    }

    func attach() {
      guard let tabBarController = enclosingTabBarController() else { return }
      interceptor.install(on: tabBarController)
    }

    private func enclosingTabBarController() -> UITabBarController? {
      if let tabBarController { return tabBarController }
      var responder: UIResponder? = view
      while let next = responder?.next {
        if let tabBarController = next as? UITabBarController { return tabBarController }
        responder = next
      }
      return nil
    }
  }
}

/// Sits in front of SwiftUI's own tab bar delegate, forwarding everything to it
/// except selection of the action tab.
final class TabSelectionInterceptor: NSObject, UITabBarControllerDelegate {
  var tabTitle: String
  var action: () -> Void
  private weak var forwardingDelegate: UITabBarControllerDelegate?

  init(tabTitle: String, action: @escaping () -> Void) {
    self.tabTitle = tabTitle
    self.action = action
  }

  func install(on tabBarController: UITabBarController) {
    guard tabBarController.delegate !== self else { return }
    forwardingDelegate = tabBarController.delegate
    tabBarController.delegate = self
  }

  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
    if tab.title == tabTitle {
      action()
      return false
    }
    return forwardingDelegate?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
  }

  func tabBarController(_ tabBarController: UITabBarController,
                        shouldSelect viewController: UIViewController) -> Bool {
    if viewController.tabBarItem.title == tabTitle {
      action()
      return false
    }
    return forwardingDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (forwardingDelegate?.responds(to: selector) ?? false)
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if let forwardingDelegate, forwardingDelegate.responds(to: selector) { return forwardingDelegate }
    return super.forwardingTarget(for: selector)
  }
}
