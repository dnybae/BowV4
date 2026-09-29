import Foundation
import ImageIO
import UIKit

enum PayeeLogoImage {
  static func preparedData(from data: Data) throws -> Data {
    guard data.count <= 50_000_000 else { throw ImportError.tooLarge }
    guard let source = CGImageSourceCreateWithData(data as CFData, [
      kCGImageSourceShouldCache: false
    ] as CFDictionary),
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 256
      ] as CFDictionary),
      let result = UIImage(cgImage: thumbnail).pngData()
    else { throw ImportError.invalidImage }
    return result
  }

  enum ImportError: LocalizedError {
    case tooLarge
    case invalidImage

    var errorDescription: String? {
      switch self {
      case .tooLarge: "Choose an image smaller than 50 MB."
      case .invalidImage: "This image could not be opened. Choose another image."
      }
    }
  }
}
