import CryptoKit
import SwiftUI
import UIKit

/// A logo prepared for a square tile. See `LogoShape` for how badges and marks differ.
struct BrandLogo {
  var image: UIImage
  /// The badge's own colour, carried out to the tile's edges, or nil for a bare mark
  /// that sits inset on a plain tile.
  var background: UIColor?

  nonisolated static func prepare(_ source: UIImage) -> BrandLogo? {
    guard let cgImage = source.cgImage, let result = LogoShape.prepare(cgImage) else { return nil }
    switch result.kind {
    case .badge(let pixel):
      return BrandLogo(
        image: UIImage(cgImage: result.image),
        background: UIColor(
          red: CGFloat(pixel.red) / 255, green: CGFloat(pixel.green) / 255,
          blue: CGFloat(pixel.blue) / 255, alpha: 1
        )
      )
    case .mark:
      return BrandLogo(image: UIImage(cgImage: result.image), background: nil)
    }
  }
}

/// Downloads and prepares logos once, so rows don't redo the pixel work while scrolling.
enum BrandLogoStore {
  private final class Box {
    let logo: BrandLogo
    init(_ logo: BrandLogo) { self.logo = logo }
  }

  private nonisolated(unsafe) static let cache = NSCache<NSString, Box>()

  nonisolated static func cached(_ key: String) -> BrandLogo? {
    cache.object(forKey: key as NSString)?.logo
  }

  nonisolated static func logo(for url: URL) async -> BrandLogo? {
    let key = url.absoluteString
    if let cached = cached(key) { return cached }
    guard let (data, response) = try? await BowImageSession.shared.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let image = UIImage(data: data) else { return nil }
    return store(BrandLogo.prepare(image), key: key)
  }

  nonisolated static func logo(for data: Data) -> BrandLogo? {
    let key = "custom-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    if let cached = cached(key) { return cached }
    guard let image = UIImage(data: data) else { return nil }
    // A photo with no transparency fills the tile as-is, whatever its proportions.
    let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.cgImage?.alphaInfo)
    let logo = opaque ? BrandLogo(image: image, background: .white) : BrandLogo.prepare(image)
    return store(logo, key: key)
  }

  private nonisolated static func store(_ logo: BrandLogo?, key: String) -> BrandLogo? {
    if let logo { cache.setObject(Box(logo), forKey: key as NSString) }
    return logo
  }
}

/// A prepared logo laid out in a square tile: full-bleed over its own background colour,
/// or inset on the tile when it's a bare mark.
struct BrandLogoImage: View {
  var logo: BrandLogo
  var side: CGFloat

  var body: some View {
    if let background = logo.background {
      Image(uiImage: logo.image)
        .resizable()
        .scaledToFill()
        .frame(width: side, height: side)
        .clipped()
        .background(Color(uiColor: background))
    } else {
      Image(uiImage: logo.image)
        .resizable()
        .scaledToFit()
        .padding(side * 0.16)
        .frame(width: side, height: side)
        .background(.white)
    }
  }
}
