import SwiftUI

struct MerchantLogoView: View {
  @AppStorage("bow.logoDevPublishableKey") private var publishableKey = ""
  var payee: String

  private var logoURL: URL? {
    let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = payee.trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.hasPrefix("pk_"), !name.isEmpty else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "img.logo.dev"
    let domain = name.lowercased()
    let isDomain = !domain.contains(" ") && domain.contains(".")
      && domain.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil
    components.path = isDomain ? "/\(domain)" : "/name/\(name)"
    components.queryItems = [
      URLQueryItem(name: "token", value: key),
      URLQueryItem(name: "size", value: "80"),
      URLQueryItem(name: "format", value: "png"),
      URLQueryItem(name: "fallback", value: "404")
    ]
    return components.url
  }

  var body: some View {
    Group {
      if let logoURL {
        AsyncImage(url: logoURL) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          fallback
        }
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
    Text(String(payee.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
      .font(.subheadline.weight(.bold))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
