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
  /// The offset at rest with a large title fully expanded. Scrolling to the content's top edge
  /// alone would leave the large title collapsed.
  @State private var restingOffset: CGFloat?

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .onScrollGeometryChange(for: ScrollTop.self) { geometry in
        ScrollTop(offset: geometry.contentOffset.y, inset: geometry.contentInsets.top)
      } action: { _, top in
        // The top inset is largest while a large title is expanded; bouncing doesn't change it.
        print("SCROLLDBG \(tab) offset=\(top.offset) inset=\(top.inset)")
        let resting = min(restingOffset ?? -top.inset, -top.inset)
        restingOffset = resting
        center.setScrolled(top.offset > resting + 1, for: tab)
      }
      .onChange(of: center.scrollToTopRequests[tab, default: 0]) { _, _ in
        withAnimation(Bow.motion(reduceMotion: reduceMotion)) {
          if let restingOffset {
            position.scrollTo(y: restingOffset)
          } else {
            position.scrollTo(edge: .top)
          }
        }
      }
  }
}

private struct ScrollTop: Equatable {
  var offset: CGFloat
  var inset: CGFloat
}

extension View {
  /// Put on a tab's main List or ScrollView so reselecting the tab scrolls it back to the top.
  func scrollsToTopOnReselect(of tab: HomeTab) -> some View {
    modifier(ScrollToTopOnReselect(tab: tab))
  }
}
