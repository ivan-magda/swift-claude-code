import Foundation

public enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let int = try? container.decode(Int.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Cannot decode JSONValue"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let boolValue):
      try container.encode(boolValue)
    case .int(let intValue):
      try container.encode(intValue)
    case .double(let doubleValue):
      try container.encode(doubleValue)
    case .string(let stringValue):
      try container.encode(stringValue)
    case .array(let arrayValue):
      try container.encode(arrayValue)
    case .object(let objectValue):
      try container.encode(objectValue)
    }
  }
}

// MARK: - Convenience accessors

extension JSONValue {
  public var stringValue: String? {
    if case .string(let stringValue) = self {
      return stringValue
    }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let value) = self {
      return value
    }
    return nil
  }

  public var intValue: Int? {
    if case .int(let value) = self {
      return value
    }
    if case .double(let value) = self {
      return Int(value)
    }
    return nil
  }

  public subscript(key: String) -> JSONValue? {
    if case .object(let dict) = self {
      return dict[key]
    }
    return nil
  }
}

// MARK: - ExpressibleBy literals

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .int(value)
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
  }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
