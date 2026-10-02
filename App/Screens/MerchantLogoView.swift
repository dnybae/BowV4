import SwiftUI

struct MerchantLogoView: View {
  @Environment(\.payeeLogoDirectory) private var directory
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var merchantName: String
  var domain: String? = nil
  var kind: BudgetTransactionKind? = nil
  var envelopeName: String? = nil
  var appearanceOverride: PayeeLogoAppearance? = nil
  var size: CGFloat = 38
  var style: Style = .plain
  @ScaledMetric private var scale: CGFloat = 1

  enum Style {
    /// A grey well, for list rows.
    case plain
    /// The white glossy tile used by identity blocks and context cards.
    case glossy
  }

  /// The logo grows with Dynamic Type, capped so rows stay proportionate.
  private var side: CGFloat { size * min(scale, Bow.maxGraphicScale) }

  private var appearance: PayeeLogoAppearance? {
    appearanceOverride ?? directory.appearance(for: merchantName)
  }

  var body: some View {
    switch style {
    case .plain:
      logo
        .background(Bow.well,
                    in: RoundedRectangle(cornerRadius: side * 0.26))
        .clipShape(RoundedRectangle(cornerRadius: side * 0.26))
        .accessibilityHidden(true)
    case .glossy:
      logo
        .bowGlossyTileBackground(side: side)
        .accessibilityHidden(true)
    }
  }

  private var logo: some View {
    Group {
      if kind == .transfer {
        systemIcon
      } else if appearance?.source == .custom,
                let data = appearance?.imageData,
                let image = CustomLogoCache.image(for: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: side, height: side)
      } else if appearance?.source == .logoDev {
        // The logo fades in over the fallback symbol instead of popping in.
        AsyncImage(
          url: LogoDev.logoURL(
            domain: appearance?.domain ?? domain,
            merchantName: appearance?.name ?? merchantName
          ),
          transaction: Transaction(animation: Bow.motion(reduceMotion: reduceMotion))
        ) { phase in
          if let image = phase.image {
            image.resizable()
              .scaledToFill()
              .frame(width: side, height: side)
              .transition(.opacity)
          } else {
            systemIcon
              .transition(.opacity)
          }
        }
      } else {
        systemIcon
      }
    }
    .frame(width: side, height: side)
  }

  private var systemIcon: some View {
    Image(systemName: TransactionIconSymbol.name(
      for: kind, payee: merchantName, envelope: envelopeName
    ))
      .font(.system(size: side * 0.44, weight: .medium))
      .foregroundStyle(Bow.inkSoft)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Decoded custom logos, so a row doesn't decode its image data on every render.
private enum CustomLogoCache {
  private static let cache = NSCache<NSData, UIImage>()

  static func image(for data: Data) -> UIImage? {
    let key = data as NSData
    if let cached = cache.object(forKey: key) { return cached }
    guard let image = UIImage(data: data) else { return nil }
    cache.setObject(image, forKey: key)
    return image
  }
}
