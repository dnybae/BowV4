import CoreGraphics

/// Works out how a brand logo should sit in a square tile.
///
/// Logos come in two kinds. A badge is drawn on its own solid shape (a square, rounded
/// square, or circle), like Whole Foods or Uber; it should fill the tile, with the shape's
/// colour carried out into the corners. A mark is a bare glyph or wordmark on transparency,
/// like Apple or Netflix; it sits inset on a plain tile.
enum LogoShape {
  struct Pixel: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    func distance(to other: Pixel) -> Int {
      abs(Int(red) - Int(other.red)) + abs(Int(green) - Int(other.green))
        + abs(Int(blue) - Int(other.blue))
    }
  }

  enum Kind: Equatable {
    case badge(background: Pixel)
    case mark
  }

  struct Result {
    /// The visible logo with transparent margins trimmed. Badges are fully opaque, with the
    /// background colour outside the shape and white behind any cut-outs inside it.
    var image: CGImage
    var kind: Kind
  }

  nonisolated static func prepare(_ source: CGImage, maxPixelSize: Int = 256) -> Result? {
    let scale = min(1, CGFloat(maxPixelSize) / CGFloat(max(source.width, source.height)))
    let width = max(1, Int(CGFloat(source.width) * scale))
    let height = max(1, Int(CGFloat(source.height) * scale))
    guard let context = bitmap(width: width, height: height) else { return nil }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }
    func isSolid(_ x: Int, _ y: Int) -> Bool { alpha(x, y) > 230 }
    func pixel(_ x: Int, _ y: Int) -> Pixel {
      let offset = (y * width + x) * 4
      return Pixel(red: data[offset], green: data[offset + 1], blue: data[offset + 2])
    }

    // Trim transparent margins.
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
      for x in 0..<width where alpha(x, y) > 12 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let boxWidth = maxX - minX + 1
    let boxHeight = maxY - minY + 1
    let crop = CGRect(x: minX, y: minY, width: boxWidth, height: boxHeight)
    guard let trimmed = context.makeImage()?.cropping(to: crop) else { return nil }

    // The outer silhouette, row by row: everything between the first and last solid pixel.
    // Holes such as cut-out lettering count as inside.
    var spans: [ClosedRange<Int>?] = []
    var hullArea = 0
    for y in minY...maxY {
      let first = (minX...maxX).first { isSolid($0, y) }
      let last = (minX...maxX).last { isSolid($0, y) }
      if let first, let last {
        spans.append(first...last)
        hullArea += last - first + 1
      } else {
        spans.append(nil)
      }
    }

    let aspect = Double(boxWidth) / Double(boxHeight)
    // A circle fills π/4 ≈ 0.785 of its box; squares and rounded squares fill more.
    let hullCoverage = Double(hullArea) / Double(boxWidth * boxHeight)
    guard (0.85...1.18).contains(aspect), hullCoverage > 0.74 else {
      return Result(image: trimmed, kind: .mark)
    }

    // Sample just inside the silhouette's left and right edges, past anti-aliasing.
    let inset = max(2, boxWidth / 64)
    var outline: [Pixel] = []
    for (row, span) in spans.enumerated() {
      guard let span else { continue }
      let y = minY + row
      for x in [span.lowerBound + inset, span.upperBound - inset]
      where span.contains(x) && isSolid(x, y) {
        outline.append(pixel(x, y))
      }
    }
    guard let background = dominant(outline) else {
      return Result(image: trimmed, kind: .mark)
    }

    // A badge has content inside its shape. A solid single-colour glyph (a filled square
    // icon, say) has nothing to show on a tile of its own colour, so it stays a mark.
    var contrasting = 0
    for (row, span) in spans.enumerated() {
      guard let span else { continue }
      for x in span where !isSolid(x, minY + row)
        || pixel(x, minY + row).distance(to: background) > 90 {
        contrasting += 1
      }
    }
    guard Double(contrasting) / Double(hullArea) > 0.03 else {
      return Result(image: trimmed, kind: .mark)
    }

    // Flatten: background colour outside the silhouette, white behind cut-outs, logo on top.
    guard let flat = bitmap(width: boxWidth, height: boxHeight),
          let out = flat.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    for row in 0..<boxHeight {
      let y = minY + row
      for column in 0..<boxWidth {
        let x = minX + column
        // Only true holes get white; the anti-aliased rim blends into the background.
        let inside = spans[row].map {
          ($0.lowerBound + inset...max($0.lowerBound + inset, $0.upperBound - inset)).contains(x)
        } ?? false
        let under = inside ? Pixel(red: 255, green: 255, blue: 255) : background
        let source = (y * width + x) * 4
        let target = (row * boxWidth + column) * 4
        let a = Int(data[source + 3])
        out[target] = UInt8(Int(data[source]) + Int(under.red) * (255 - a) / 255)
        out[target + 1] = UInt8(Int(data[source + 1]) + Int(under.green) * (255 - a) / 255)
        out[target + 2] = UInt8(Int(data[source + 2]) + Int(under.blue) * (255 - a) / 255)
        out[target + 3] = 255
      }
    }
    guard let image = flat.makeImage() else { return nil }
    return Result(image: image, kind: .badge(background: background))
  }

  /// The mean colour, if at least three quarters of the samples are close to it.
  private nonisolated static func dominant(_ pixels: [Pixel]) -> Pixel? {
    guard !pixels.isEmpty else { return nil }
    let count = pixels.count
    let sums = pixels.reduce(into: (0, 0, 0)) {
      $0.0 += Int($1.red); $0.1 += Int($1.green); $0.2 += Int($1.blue)
    }
    let mean = Pixel(red: UInt8(sums.0 / count), green: UInt8(sums.1 / count),
                     blue: UInt8(sums.2 / count))
    let close = pixels.filter { $0.distance(to: mean) < 60 }.count
    return Double(close) / Double(count) > 0.75 ? mean : nil
  }

  private nonisolated static func bitmap(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }
}
