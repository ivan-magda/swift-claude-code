import Foundation
import Testing

@testable import Core

// MARK: - ContentBlock

@Suite("ContentBlock")
struct ContentBlockTests {
  @Test func decodesText() throws {
    let json = #"{"type": "text", "text": "Hello world"}"#
    let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
    #expect(block == .text("Hello world"))
  }

  @Test func decodesToolUse() throws {
    let json = """
      {
          "type": "tool_use",
          "id": "toolu_123",
          "name": "bash",
          "input": {"command": "ls"}
      }
      """
    let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
    #expect(
      block
        == .toolUse(
          id: "toolu_123",
          name: "bash",
          input: .object(["command": .string("ls")])
        )
    )
  }

  @Test func decodesToolResult() throws {
    let json = """
      {
          "type": "tool_result",
          "tool_use_id": "toolu_789",
          "content": "output text",
          "is_error": true
      }
      """
    let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
    #expect(block == .toolResult(toolUseId: "toolu_789", content: "output text", isError: true))
  }

  @Test func encodesToolResult() throws {
    let block = ContentBlock.toolResult(
      toolUseId: "toolu_456", content: "file1.txt", isError: false
    )

    let data = try JSONEncoder().encode(block)
    let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
    let type = try #require(json["type"]?.stringValue)

    #expect(type == "tool_result")
    #expect(json["tool_use_id"]?.stringValue == "toolu_456")
    #expect(json["content"]?.stringValue == "file1.txt")
  }

  @Test func textContentJoinsTextBlocks() {
    let blocks: [ContentBlock] = [
      .text("Hello"),
      .toolUse(id: "t1", name: "bash", input: .object(["command": "ls"])),
      .text("World"),
    ]
    #expect(blocks.textContent == "Hello\nWorld")
  }

  @Test func textContentEmptyWhenNoTextBlocks() {
    let blocks: [ContentBlock] = [
      .toolUse(id: "t1", name: "bash", input: .object(["command": "ls"])),
      .toolResult(toolUseId: "t1", content: "output", isError: false),
    ]
    #expect(blocks.textContent == "")
  }
}

// MARK: - Message

@Suite("Message")
struct MessageTests {
  @Test func userConvenience() {
    let msg = Message.user("Hello")
    #expect(msg.role == .user)
    #expect(msg.content == [.text("Hello")])
  }

  @Test func roundTrips() throws {
    let msg = Message(
      role: .assistant,
      content: [
        .text("Let me run that."),
        .toolUse(id: "toolu_abc", name: "bash", input: .object(["command": "pwd"])),
      ]
    )

    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: data)

    #expect(decoded == msg)
  }
}

// MARK: - StopReason

@Suite("StopReason")
struct StopReasonTests {
  @Test(
    "Decodes from JSON",
    arguments: [
      (#""end_turn""#, StopReason.endTurn),
      (#""tool_use""#, StopReason.toolUse),
      (#""max_tokens""#, StopReason.maxTokens),
    ]
  )
  func decodes(json: String, expected: StopReason) throws {
    let decoded = try JSONDecoder().decode(StopReason.self, from: Data(json.utf8))
    #expect(decoded == expected)
  }
}

// MARK: - APIRequest

@Suite("APIRequest")
struct APIRequestTests {
  @Test func encodesCorrectly() throws {
    let request = APIRequest(
      model: "claude-sonnet-4-6",
      maxTokens: 1024,
      system: "You are helpful.",
      messages: [.user("Hi")],
      tools: [
        ToolDefinition(
          name: "bash",
          description: "Run a command",
          inputSchema: .object([
            "type": "object",
            "properties": .object([
              "command": .object(["type": "string"])
            ]),
            "required": .array(["command"]),
          ])
        )
      ]
    )

    let data = try JSONEncoder().encode(request)
    let dict = try JSONDecoder().decode([String: JSONValue].self, from: data)

    #expect(dict["model"]?.stringValue == "claude-sonnet-4-6")
    #expect(dict["max_tokens"] != nil)
  }
}

// MARK: - APIResponse

@Suite("APIResponse")
struct APIResponseTests {
  @Test func decodes() throws {
    let json = """
      {
          "id": "msg_abc123",
          "type": "message",
          "role": "assistant",
          "content": [
              {"type": "text", "text": "Here are the files."}
          ],
          "stop_reason": "end_turn",
          "usage": {
              "input_tokens": 100,
              "output_tokens": 50
          }
      }
      """
    let response = try JSONDecoder().decode(APIResponse.self, from: Data(json.utf8))
    #expect(response.id == "msg_abc123")
    #expect(response.stopReason == .endTurn)
    #expect(response.usage.inputTokens == 100)
    #expect(response.content.count == 1)
  }
}

// MARK: - APIError

@Suite("APIError")
struct APIErrorTests {
  @Test func decodesErrorResponse() throws {
    let json = """
      {
          "type": "error",
          "error": {
              "type": "invalid_request_error",
              "message": "max_tokens must be positive"
          }
      }
      """
    let response = try JSONDecoder().decode(APIErrorResponse.self, from: Data(json.utf8))
    #expect(response.error.type == "invalid_request_error")
    #expect(response.error.message == "max_tokens must be positive")
  }
}
