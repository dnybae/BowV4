import SwiftUI

struct MerchantLogoView: View {
  var merchantName: String
  var domain: String? = nil

  var body: some View {
    AsyncImage(url: LogoDev.logoURL(domain: domain, merchantName: merchantName)) { phase in
      if let image = phase.image {
        image.resizable().scaledToFit()
      } else {
        fallback
      }
    }
    .frame(width: 38, height: 38)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .accessibilityHidden(true)
  }

  private var fallback: some View {
    Image(systemName: "storefront")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
