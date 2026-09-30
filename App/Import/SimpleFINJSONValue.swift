import Foundation

/// Any JSON value, used to keep SimpleFIN's open-ended `extra` object intact.
enum SimpleFINJSONValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: SimpleFINJSONValue])
  case array([SimpleFINJSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([SimpleFINJSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: SimpleFINJSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var stringValue: String? {
    switch self {
    case .string(let value): value
    case .number(let value): abs(value) < 1e15 && value.rounded() == value ? String(Int64(value)) : String(value)
    default: nil
    }
  }
}
