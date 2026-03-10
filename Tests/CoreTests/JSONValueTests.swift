import Foundation
import Testing

@testable import Core

@Suite("JSONValue")
struct JSONValueTests {
  @Test func decodesString() throws {
    let data = Data(#""hello""#.utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value == .string("hello"))
    #expect(value.stringValue == "hello")
  }

  @Test func decodesObject() throws {
    let json = #"{"command": "ls -la", "count": 42}"#
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    #expect(value["command"]?.stringValue == "ls -la")
  }

  @Test func roundTrips() throws {
    let original: JSONValue = .object([
      "name": "bash",
      "args": .array(["echo", "hello"]),
      "verbose": .bool(true),
      "count": .int(3),
      "ratio": .double(1.5),
      "nothing": .null,
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == original)
  }

  @Test func stringLiteral() {
    let value: JSONValue = "hello"
    #expect(value == .string("hello"))
  }

  @Test func integerLiteral() {
    let value: JSONValue = 42
    #expect(value == .int(42))
  }

  @Test func booleanLiteral() {
    let value: JSONValue = true
    #expect(value == .bool(true))
  }

  @Test func nilLiteral() {
    let value: JSONValue = nil
    #expect(value == .null)
  }

  @Test func decodingInvalidJSONThrows() {
    #expect(throws: DecodingError.self) {
      // A bare, unquoted token is not valid JSON
      try JSONDecoder().decode(JSONValue.self, from: Data("invalid".utf8))
    }
  }
}
