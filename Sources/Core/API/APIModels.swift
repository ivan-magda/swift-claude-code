import Foundation

// MARK: - Content blocks

public enum ContentBlock: Sendable, Equatable {
  case text(String)
  case toolUse(id: String, name: String, input: JSONValue)
  case toolResult(toolUseId: String, content: String, isError: Bool)
}

extension ContentBlock: Codable {
  private enum BlockType: String, Codable {
    case text = "text"
    case toolUse = "tool_use"
    case toolResult = "tool_result"
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case text
    case id
    case name
    case input
    case toolUseId = "tool_use_id"
    case content
    case isError = "is_error"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(BlockType.self, forKey: .type)

    switch type {
    case .text:
      let text = try container.decode(String.self, forKey: .text)
      self = .text(text)
    case .toolUse:
      let id = try container.decode(String.self, forKey: .id)
      let name = try container.decode(String.self, forKey: .name)
      let input = try container.decode(JSONValue.self, forKey: .input)
      self = .toolUse(id: id, name: name, input: input)
    case .toolResult:
      let toolUseId = try container.decode(String.self, forKey: .toolUseId)
      let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
      let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
      self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode(BlockType.text, forKey: .type)
      try container.encode(text, forKey: .text)
    case .toolUse(let id, let name, let input):
      try container.encode(BlockType.toolUse, forKey: .type)
      try container.encode(id, forKey: .id)
      try container.encode(name, forKey: .name)
      try container.encode(input, forKey: .input)
    case .toolResult(let toolUseId, let content, let isError):
      try container.encode(BlockType.toolResult, forKey: .type)
      try container.encode(toolUseId, forKey: .toolUseId)
      try container.encode(content, forKey: .content)
      try container.encode(isError, forKey: .isError)
    }
  }
}

extension Array where Element == ContentBlock {
  public var textContent: String {
    compactMap {
      if case .text(let value) = $0 {
        value
      } else {
        nil
      }
    }
    .joined(separator: "\n")
  }
}

// MARK: - Messages

public struct Message: Codable, Sendable, Equatable {
  public enum Role: String, Codable, Sendable {
    case user
    case assistant
  }

  public let role: Role
  public let content: [ContentBlock]

  public init(role: Role, content: [ContentBlock]) {
    self.role = role
    self.content = content
  }

  public static func user(_ text: String) -> Message {
    Message(role: .user, content: [.text(text)])
  }

  public static func assistant(_ text: String) -> Message {
    Message(role: .assistant, content: [.text(text)])
  }
}

// MARK: - Stop reason

public enum StopReason: String, Codable, Sendable {
  case endTurn = "end_turn"
  case toolUse = "tool_use"
  case maxTokens = "max_tokens"
  case stopSequence = "stop_sequence"
}

// MARK: - Token usage

public struct Usage: Codable, Sendable {
  public let inputTokens: Int
  public let outputTokens: Int

  private enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }
}

// MARK: - API response

public struct APIResponse: Codable, Sendable {
  public let id: String
  public let type: String
  public let role: String
  public let content: [ContentBlock]
  public let stopReason: StopReason?
  public let usage: Usage

  private enum CodingKeys: String, CodingKey {
    case id, type, role, content, usage
    case stopReason = "stop_reason"
  }
}

// MARK: - Tool definition

public struct ToolDefinition: Codable, Sendable {
  public let name: String
  public let description: String
  public let inputSchema: JSONValue

  public init(name: String, description: String, inputSchema: JSONValue) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }

  private enum CodingKeys: String, CodingKey {
    case name, description
    case inputSchema = "input_schema"
  }
}

// MARK: - API request

public struct APIRequest: Codable, Sendable {
  public let model: String
  public let maxTokens: Int
  public let system: String?
  public let messages: [Message]
  public let tools: [ToolDefinition]?

  public init(
    model: String,
    maxTokens: Int = 4096,
    system: String? = nil,
    messages: [Message],
    tools: [ToolDefinition]? = nil
  ) {
    self.model = model
    self.maxTokens = maxTokens
    self.system = system
    self.messages = messages
    self.tools = tools
  }

  private enum CodingKeys: String, CodingKey {
    case model, system, messages, tools
    case maxTokens = "max_tokens"
  }
}

// MARK: - API error

public struct APIError: Error, Codable, Sendable, CustomStringConvertible {
  public let type: String
  public let message: String

  public var description: String {
    "\(type): \(message)"
  }
}

public struct APIErrorResponse: Codable, Sendable {
  public let type: String
  public let error: APIError
}
