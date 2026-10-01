import SwiftUI

/// Coordinates what happens when the user taps the tab they're already on.
/// Screens report whether they're scrolled; the tab bar asks them to scroll back up.
@Observable
final class TabReselectCenter {
  private(set) var scrollToTopRequests: [HomeTab: Int] = [:]
  private var scrolledTabs: Set<HomeTab> = []

  func isScrolled(_ tab: HomeTab) -> Bool { scrolledTabs.contains(tab) }

  func setScrolled(_ isScrolled: Bool, for tab: HomeTab) {
    if isScrolled { scrolledTabs.insert(tab) } else { scrolledTabs.remove(tab) }
  }

  func requestScrollToTop(_ tab: HomeTab) {
    scrollToTopRequests[tab, default: 0] += 1
  }
}

enum HomeTab: Hashable {
  case budget
  case transactions
  case calendar
  case accounts
  case addTransaction
}

private struct ScrollToTopOnReselect: ViewModifier {
  @Environment(TabReselectCenter.self) private var center
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var tab: HomeTab
  @State private var position = ScrollPosition(edge: .top)

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top > 1
      } action: { _, isScrolled in
        center.setScrolled(isScrolled, for: tab)
      }
      .onChange(of: center.scrollToTopRequests[tab, default: 0]) { _, _ in
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
          position.scrollTo(edge: .top)
        }
      }
  }
}

extension View {
  /// Put on a tab's main List or ScrollView so reselecting the tab scrolls it back to the top.
  func scrollsToTopOnReselect(of tab: HomeTab) -> some View {
    modifier(ScrollToTopOnReselect(tab: tab))
  }
}
