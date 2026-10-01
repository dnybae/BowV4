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

/// A URL session with a disk cache for logos.
enum BowImageSession {
  static let shared: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: configuration)
  }()
}
