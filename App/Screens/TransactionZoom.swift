import SwiftUI

extension EnvironmentValues {
  @Entry var transactionZoomNamespace: Namespace.ID? = nil
  @Entry var transactionZoomPrefix = ""
}

extension View {
  @ViewBuilder
  func bowTransactionZoomSource(_ id: String, namespace: Namespace.ID?, prefix: String) -> some View {
    if let namespace {
      matchedTransitionSource(id: prefix + id, in: namespace)
    } else { self }
  }

  @ViewBuilder
  func bowTransactionZoomDestination(_ id: String, namespace: Namespace.ID, enabled: Bool) -> some View {
    if enabled {
      navigationTransition(.zoom(sourceID: id, in: namespace))
    } else { self }
  }
}
