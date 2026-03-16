import Foundation
import Testing

@testable import Core

// MARK: - Tool dispatch

@Suite("Agent tool dispatch")
struct AgentToolDispatchTests {
  @Test func unknownToolReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "unknown_tool",
      input: .object([:])
    )
    #expect(result == .failure(.unknownTool("unknown_tool")))
  }

  @Test func missingCommandReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "bash",
      input: .object([:])
    )
    #expect(result == .failure(.missingParameter("command")))
  }

  @Test func validCommandReturnsOutput() async throws {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "bash",
      input: .object(["command": "echo hello"])
    )
    let output = try result.get()
    #expect(output.contains("hello"))
  }
}

// MARK: - Todo tool dispatch

@Suite("Todo tool dispatch")
struct TodoToolDispatchTests {
  @Test func missingItemsReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "todo",
      input: .object([:])
    )
    #expect(result == .failure(.missingParameter("items")))
  }

  @Test func missingItemFieldReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "todo",
      input: .object([
        "items": .array([.object(["id": "1", "text": "task"])])
      ])
    )
    #expect(result == .failure(.missingParameter("items[].status")))
  }

  @Test func invalidStatusReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "todo",
      input: .object([
        "items": .array([
          .object(["id": "1", "text": "task", "status": "unknown"])
        ])
      ])
    )
    #expect(result == .failure(.executionFailed("Invalid status 'unknown' for item 1")))
  }

  @Test func validInputReturnsRenderedOutput() async throws {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "todo",
      input: .object([
        "items": .array([
          .object(["id": "1", "text": "My task", "status": "pending"])
        ])
      ])
    )
    let output = try result.get()
    #expect(output.contains("[ ] My task"))
  }
}
