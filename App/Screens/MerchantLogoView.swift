import SwiftUI

struct MerchantLogoView: View {
  @Environment(\.payeeLogoDirectory) private var directory
  var merchantName: String
  var domain: String? = nil
  var kind: BudgetTransactionKind? = nil
  var categoryName: String? = nil
  var appearanceOverride: PayeeLogoAppearance? = nil
  var size: CGFloat = 38

  private var appearance: PayeeLogoAppearance? {
    appearanceOverride ?? directory.appearance(for: merchantName)
  }

  var body: some View {
    Group {
      if kind == .transfer {
        systemIcon
      } else if appearance?.source == .custom,
                let data = appearance?.imageData,
                let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: size - 10, height: size - 10)
      } else if appearance?.source == .logoDev {
        AsyncImage(url: LogoDev.logoURL(
          domain: appearance?.domain ?? domain,
          merchantName: appearance?.name ?? merchantName
        )) { phase in
          if let image = phase.image {
            image.resizable()
              .scaledToFit()
              .frame(width: size - 10, height: size - 10)
          } else {
            systemIcon
          }
        }
      } else {
        systemIcon
      }
    }
    .frame(width: size, height: size)
    .background(Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: size * 0.26))
    .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
    .accessibilityHidden(true)
  }

  private var systemIcon: some View {
    Image(systemName: TransactionIconSymbol.name(
      for: kind, payee: merchantName, category: categoryName
    ))
      .font(.system(size: size * 0.44, weight: .medium))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
