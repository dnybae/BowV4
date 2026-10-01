import SwiftUI

/// iOS 27 refinements, applied only where the system supports them. On iOS 26 these return the view unchanged.
extension View {
  /// Long lists: the navigation bar tucks away while scrolling down, like the tab bar.
  @ViewBuilder
  func bowMinimizesNavigationBarOnScroll() -> some View {
    if #available(iOS 27.0, *) {
      toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
    } else {
      self
    }
  }

  /// Rows outside a List (Calendar's day card) get the same swipe actions as Spending.
  @ViewBuilder
  func bowSwipeActionsContainer() -> some View {
    if #available(iOS 27.0, *) {
      swipeActionsContainer()
    } else {
      self
    }
  }

  /// Merchant logos load through one cached session, so they don't download again while scrolling.
  @ViewBuilder
  func bowCachedAsyncImages() -> some View {
    if #available(iOS 27.0, *) {
      asyncImageURLSession(BowImageSession.shared)
    } else {
      self
    }
  }
}

extension View {
  /// Secondary toolbar actions (Hide, Delete): the iOS 27 overflow menu, or a More menu on iOS 26.
  @ViewBuilder
  func bowToolbarOverflow<Content: View>(isEnabled: Bool = true, @ViewBuilder _ content: () -> Content) -> some View {
    let items = content()
    if !isEnabled {
      self
    } else if #available(iOS 27.0, *) {
      toolbarOverflowMenu { items }
    } else {
      toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu("More", systemImage: "ellipsis") { items }
        }
      }
    }
  }
}

/// A URL session with a disk cache for logos.
enum BowImageSession {
  static let shared: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: configuration)
  }()
}
