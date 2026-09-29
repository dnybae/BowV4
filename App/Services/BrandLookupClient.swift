import Foundation

struct BrandSearchResult: Decodable, Identifiable, Sendable {
  var name: String
  var domain: String
  var logoURL: URL?

  var id: String { domain }

  var compactLogoURL: URL? {
    guard let logoURL, var components = URLComponents(url: logoURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    var query = components.queryItems ?? []
    query.removeAll { ["size", "format", "fallback"].contains($0.name) }
    query += [
      URLQueryItem(name: "size", value: "32"),
      URLQueryItem(name: "format", value: "png"),
      URLQueryItem(name: "fallback", value: "404")
    ]
    components.queryItems = query
    return components.url
  }

  enum CodingKeys: String, CodingKey {
    case name, domain
    case logoURL = "logo_url"
  }
}

struct TransactionBrandResult: Decodable, Sendable {
  var name: String
  var domain: String
  var description: String?
}

enum BrandLookupClient {
  static var isConfigured: Bool { baseURL != nil }

  private static var baseURL: URL? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "BrandLookupBaseURL") as? String,
          let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
    return url
  }

  static func search(_ query: String) async throws -> [BrandSearchResult] {
    guard let baseURL else { return [] }
    var url = baseURL.appending(path: "search")
    url.append(queryItems: [URLQueryItem(name: "q", value: query)])
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response)
    return try JSONDecoder().decode([BrandSearchResult].self, from: data)
  }

  static func identify(_ descriptor: String) async throws -> TransactionBrandResult? {
    guard let baseURL else { return nil }
    var request = URLRequest(url: baseURL.appending(path: "identify"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(IdentifyRequest(descriptor: descriptor))
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw BrandLookupError.invalidResponse }
    if http.statusCode == 404 { return nil }
    try validate(response)
    return try JSONDecoder().decode(TransactionBrandResult.self, from: data)
  }

  private static func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw BrandLookupError.invalidResponse
    }
  }
}

private struct IdentifyRequest: Encodable {
  var descriptor: String
}

private enum BrandLookupError: Error {
  case invalidResponse
}
