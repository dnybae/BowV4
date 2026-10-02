import SwiftUI

struct MerchantLogoView: View {
  @Environment(\.payeeLogoDirectory) private var directory
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var merchantName: String
  var domain: String? = nil
  var kind: BudgetTransactionKind? = nil
  var envelopeName: String? = nil
  var appearanceOverride: PayeeLogoAppearance? = nil
  var fallbackSymbol: String? = nil
  var size: CGFloat = 38
  var style: Style = .plain
  @ScaledMetric private var scale: CGFloat = 1
  @State private var remoteLogo: BrandLogo?
  /// Watched so turning Merchant logos off or on updates every logo at once.
  @AppStorage(MerchantLogoSettings.key) private var showsMerchantLogos = true

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

  private var logoURL: URL? {
    guard showsMerchantLogos, kind != .transfer, appearance?.source == .logoDev else { return nil }
    return LogoDev.logoURL(
      domain: appearance?.domain ?? domain,
      merchantName: appearance?.name ?? merchantName
    )
  }

  private var customData: Data? {
    guard kind != .transfer, appearance?.source == .custom else { return nil }
    return appearance?.imageData
  }

  private var logo: some View {
    Group {
      if let customData, let custom = BrandLogoStore.logo(for: customData) {
        BrandLogoImage(logo: custom, side: side)
      } else if let remoteLogo = remoteLogo ?? logoURL.flatMap({ BrandLogoStore.cached($0.absoluteString) }) {
        // The logo fades in over the fallback symbol instead of popping in.
        BrandLogoImage(logo: remoteLogo, side: side)
          .transition(.opacity)
      } else {
        systemIcon
          .transition(.opacity)
      }
    }
    .frame(width: side, height: side)
    .task(id: logoURL) {
      remoteLogo = nil
      guard let logoURL, BrandLogoStore.cached(logoURL.absoluteString) == nil else { return }
      let loaded = await BrandLogoStore.logo(for: logoURL)
      guard !Task.isCancelled else { return }
      withAnimation(Bow.motion(reduceMotion: reduceMotion)) { remoteLogo = loaded }
    }
  }

  private var systemIcon: some View {
    Image(systemName: fallbackSymbol ?? TransactionIconSymbol.name(
      for: kind, payee: merchantName, envelope: envelopeName
    ))
      .font(.system(size: side * 0.44, weight: .medium))
      .foregroundStyle(Bow.inkSoft)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
