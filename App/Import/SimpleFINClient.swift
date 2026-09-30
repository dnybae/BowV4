import Foundation

enum SimpleFINError: LocalizedError {
  case invalidToken
  case invalidAccessURL
  case credentialStorage
  case tokenRejected
  case accessRejected
  case paymentRequired
  case server(Int)
  case invalidResponse
  case invalidAmount
  case noConnection
  case refreshTooSoon
  case alreadyLinked
  case balanceOverflow
  case dailyLimit

  var errorDescription: String? {
    switch self {
    case .invalidToken: "Paste a valid SimpleFIN setup token."
    case .invalidAccessURL: "SimpleFIN returned an invalid access URL."
    case .credentialStorage: "The SimpleFIN connection could not be saved securely on this device."
    case .tokenRejected: "SimpleFIN rejected this one-time token. It may already have been used. Disable it in SimpleFIN and create a new token."
    case .accessRejected: "SimpleFIN access was denied. Check the connection in SimpleFIN or reconnect it in Bow."
    case .paymentRequired: "SimpleFIN requires a payment before this connection can sync."
    case .server(let code): "SimpleFIN returned HTTP \(code). Try again later."
    case .invalidResponse: "SimpleFIN returned data Bow could not read. Try again later."
    case .invalidAmount: "SimpleFIN returned a transaction amount Bow could not read."
    case .noConnection: "Connect SimpleFIN before syncing."
    case .refreshTooSoon: "SimpleFIN was checked recently. Wait about 10 minutes before refreshing again."
    case .alreadyLinked: "That Bow transaction is already linked to another SimpleFIN transaction."
    case .balanceOverflow: "The imported history is too large to adjust this account’s opening balance safely."
    case .dailyLimit: "Bow has reached SimpleFIN’s daily request limit. Sync will resume tomorrow."
    }
  }
}

struct SimpleFINAccountSet: Decodable, Sendable {
  var accounts: [SimpleFINRemoteAccount]
  var errlist: [SimpleFINRemoteError]?
  var errors: [String]?

  var messages: [String] {
    let structured = (errlist ?? []).map(\.msg)
    return (structured + (errors ?? [])).map { message in
      String(message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(250))
    }.filter { !$0.isEmpty }
  }
}

struct SimpleFINRemoteError: Decodable, Sendable {
  var msg: String
}

struct SimpleFINRemoteAccount: Decodable, Sendable {
  var id: String
  var name: String
  var connID: String?
  var currency: String
  var balance: String? = nil
  var balanceDate: TimeInterval? = nil
  var transactions: [SimpleFINRemoteTransaction]?

  enum CodingKeys: String, CodingKey {
    case id, name, currency, balance, transactions
    case connID = "conn_id"
    case balanceDate = "balance-date"
  }

  var remoteKey: String { "\(connID ?? "")|\(id)" }
}

struct SimpleFINRemoteTransaction: Decodable, Sendable {
  var id: String
  var posted: TimeInterval
  var amount: String
  var description: String
  var transactedAt: TimeInterval?
  var pending: Bool?
  var extra: [String: SimpleFINJSONValue]? = nil

  enum CodingKeys: String, CodingKey {
    case id, posted, amount, description, pending, extra
    case transactedAt = "transacted_at"
  }

  /// The protocol allows `posted` to be 0 for pending transactions even when `pending` is missing.
  var isPending: Bool { pending == true || posted <= 0 }

  /// Memo-style text a bank passes through `extra`, used as the transaction's notes.
  var memo: String {
    let keys = ["memo", "note", "notes", "Memo", "Note", "Notes"]
    for key in keys {
      if let text = extra?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
         !text.isEmpty, text.caseInsensitiveCompare(description) != .orderedSame {
        return String(text.prefix(500))
      }
    }
    return ""
  }

  var extraJSON: Data? {
    guard let extra, !extra.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try? encoder.encode(extra)
  }

  var date: Date {
    Date(timeIntervalSince1970: posted > 0 ? posted : (transactedAt ?? posted))
  }

  var amountMinor: Int64? {
    guard let amount = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
      return nil
    }
    let cents = amount * 100
    var value = cents
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .plain)
    guard cents == rounded, cents <= Decimal(Int64.max), cents >= Decimal(Int64.min) else {
      return nil
    }
    return Int64(NSDecimalNumber(decimal: cents).stringValue)
  }
}

// Banks don't always follow the spec exactly, so decoding is lenient: one malformed
// account or transaction is skipped instead of failing the whole sync.

extension SimpleFINAccountSet {
  enum CodingKeys: String, CodingKey { case accounts, errlist, errors }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accounts = try container.decode([SimpleFINLossy<SimpleFINRemoteAccount>].self, forKey: .accounts)
      .compactMap(\.value)
    errlist = (try? container.decode([SimpleFINLossy<SimpleFINRemoteError>].self, forKey: .errlist))?
      .compactMap(\.value)
    errors = (try? container.decode([SimpleFINLossy<String>].self, forKey: .errors))?
      .compactMap(\.value)
  }
}

extension SimpleFINRemoteAccount {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeLenientString(forKey: .id)
    name = (try? container.decodeLenientString(forKey: .name)) ?? ""
    connID = try? container.decodeLenientString(forKey: .connID)
    currency = try container.decodeLenientString(forKey: .currency)
    balance = try? container.decodeLenientString(forKey: .balance)
    balanceDate = container.decodeLenientTimestamp(forKey: .balanceDate)
    transactions = (try? container.decode([SimpleFINLossy<SimpleFINRemoteTransaction>].self, forKey: .transactions))?
      .compactMap(\.value)
  }
}

extension SimpleFINRemoteTransaction {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeLenientString(forKey: .id)
    guard !id.isEmpty else {
      throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
    }
    amount = try container.decodeLenientString(forKey: .amount)
    posted = container.decodeLenientTimestamp(forKey: .posted) ?? 0
    description = (try? container.decodeLenientString(forKey: .description)) ?? ""
    transactedAt = container.decodeLenientTimestamp(forKey: .transactedAt)
    pending = try? container.decode(Bool.self, forKey: .pending)
    if case .object(let object)? = try? container.decode(SimpleFINJSONValue.self, forKey: .extra) {
      extra = object
    }
  }
}

private struct SimpleFINLossy<Value: Decodable>: Decodable {
  var value: Value?

  init(from decoder: Decoder) throws {
    value = try? Value(from: decoder)
  }
}

private extension KeyedDecodingContainer {
  func decodeLenientString(forKey key: Key) throws -> String {
    if let text = try? decode(String.self, forKey: key) { return text }
    if let number = try? decode(Int64.self, forKey: key) { return String(number) }
    if let number = try? decode(Double.self, forKey: key), number.isFinite { return String(number) }
    throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing text"))
  }

  func decodeLenientTimestamp(forKey key: Key) -> TimeInterval? {
    if let number = try? decode(TimeInterval.self, forKey: key) { return number }
    if let text = try? decode(String.self, forKey: key) {
      return TimeInterval(text.trimmingCharacters(in: .whitespaces))
    }
    return nil
  }
}

struct SimpleFINClient {
  private var session: URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .never
    config.urlCache = nil
    return URLSession(configuration: config, delegate: SimpleFINRedirectGuard(), delegateQueue: nil)
  }

  func claim(setupToken: String) async throws -> URL {
    let token = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: token),
          let raw = String(data: data, encoding: .utf8),
          let url = URL(string: raw), url.scheme == "https", url.host != nil,
          url.user == nil, url.password == nil else {
      throw SimpleFINError.invalidToken
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = Data()
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw SimpleFINError.invalidResponse }
    if http.statusCode == 403 { throw SimpleFINError.tokenRejected }
    guard http.statusCode == 200,
          let rawAccess = String(data: body, encoding: .utf8),
          let accessURL = URL(string: rawAccess.trimmingCharacters(in: .whitespacesAndNewlines)),
          accessURL.scheme == "https", accessURL.host != nil,
          accessURL.user != nil, accessURL.password != nil else {
      throw http.statusCode == 200 ? SimpleFINError.invalidAccessURL : SimpleFINError.server(http.statusCode)
    }
    return accessURL
  }

  func fetch(accessURL: URL, startDate: Date) async throws -> SimpleFINAccountSet {
    guard accessURL.scheme == "https", let host = accessURL.host,
          !host.isEmpty, let user = accessURL.user,
          let password = accessURL.password,
          var components = URLComponents(url: accessURL, resolvingAgainstBaseURL: false) else {
      throw SimpleFINError.invalidAccessURL
    }
    components.user = nil
    components.password = nil
    components.path = (components.path as NSString).appendingPathComponent("accounts")
    components.queryItems = [
      URLQueryItem(name: "version", value: "2"),
      URLQueryItem(name: "pending", value: "1"),
      URLQueryItem(name: "start-date", value: String(Int(startDate.timeIntervalSince1970))),
      URLQueryItem(name: "end-date", value: String(Int(Date().timeIntervalSince1970) + 1))
    ]
    guard let url = components.url else { throw SimpleFINError.invalidAccessURL }
    var request = URLRequest(url: url)
    request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw SimpleFINError.invalidResponse }
    if http.statusCode == 403 { throw SimpleFINError.accessRejected }
    if http.statusCode == 402 { throw SimpleFINError.paymentRequired }
    guard http.statusCode == 200 else { throw SimpleFINError.server(http.statusCode) }
    guard let result = try? JSONDecoder().decode(SimpleFINAccountSet.self, from: body) else {
      throw SimpleFINError.invalidResponse
    }
    return result
  }
}

private final class SimpleFINRedirectGuard: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard request.url?.scheme == "https",
          request.url?.host == task.currentRequest?.url?.host else {
      completionHandler(nil)
      return
    }
    var redirected = request
    redirected.setValue(task.currentRequest?.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
    completionHandler(redirected)
  }
}
