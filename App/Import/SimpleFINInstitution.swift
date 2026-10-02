import Foundation

struct SimpleFINInstitution: Decodable, Sendable {
  var name: String?
  var domain: String?
  var url: String?

  var logoDomain: String? { Self.domain(from: domain) ?? Self.domain(from: url) }

  static func domain(from value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
          ["https", "http"].contains(url.scheme), let host = url.host,
          host.range(of: "^(?:[a-z0-9-]+\\.)+[a-z]{2,}$", options: .regularExpression) != nil
    else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}

struct SimpleFINRemoteConnection: Decodable, Sendable {
  var connID: String
  var name: String?
  var orgURL: String?

  enum CodingKeys: String, CodingKey {
    case connID = "conn_id", name, orgURL = "org_url"
  }
}
