import Foundation
import Testing

@testable import Core

// MARK: - Mock API client

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
  var responses: [APIResponse] = []
  private(set) var requests: [APIRequest] = []
  private var callIndex = 0

  func createMessage(request: APIRequest) async throws -> APIResponse {
    requests.append(request)
    let response = responses[callIndex]
    callIndex += 1
    return response
  }
}

private func makeAgent(
  mock: MockAPIClient = MockAPIClient()
) -> (Agent, MockAPIClient) {
  let agent = Agent(
    apiClient: mock,
    model: "test-model",
    systemPrompt: "You are a test agent."
  )
  return (agent, mock)
}

private func makeResponse(
  content: [ContentBlock],
  stopReason: StopReason = .endTurn
) -> APIResponse {
  APIResponse(
    id: "msg_test",
    type: "message",
    role: "assistant",
    content: content,
    stopReason: stopReason,
    usage: Usage(inputTokens: 10, outputTokens: 5)
  )
}

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

// MARK: - Agent loop

@Suite("Agent loop")
struct AgentLoopTests {
  @Test func returnsTextOnEndTurn() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      makeResponse(content: [.text("the answer")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "question")

    #expect(result == "the answer")
    #expect(mock.requests.count == 1)
    #expect(mock.requests[0].model == "test-model")
  }

  @Test func executesToolThenReturnsText() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // First response: ask to run a tool
      makeResponse(
        content: [
          .text("Let me check."),
          .toolUse(id: "t1", name: "bash", input: .object(["command": "echo hi"]))
        ],
        stopReason: .toolUse
      ),
      // Second response: final answer after seeing tool result
      makeResponse(content: [.text("done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "do something")

    #expect(result == "done")
    #expect(mock.requests.count == 2)

    // Second request should contain the tool result
    let secondMessages = mock.requests[1].messages
    let lastMessage = try #require(secondMessages.last)
    #expect(lastMessage.role == .user)
    #expect(
      lastMessage.content.contains(where: {
        if case .toolResult = $0 { true } else { false }
      })
    )
  }
}

// MARK: - Todo reminder

@Suite("Todo reminder")
struct TodoReminderTests {
  private static func bashToolUseResponse(id: String) -> APIResponse {
    makeResponse(
      content: [
        .toolUse(id: id, name: "bash", input: .object(["command": "echo ok"]))
      ],
      stopReason: .toolUse
    )
  }

  private static func todoToolUseResponse(id: String) -> APIResponse {
    makeResponse(
      content: [
        .toolUse(
          id: id,
          name: "todo",
          input: .object([
            "items": .array([
              .object([
                "id": "1",
                "text": "task",
                "status": "pending"
              ])
            ])
          ])
        )
      ],
      stopReason: .toolUse
    )
  }

  private static let endResponse = makeResponse(content: [.text("done")])

  private func userMessages(from mock: MockAPIClient) throws -> [[ContentBlock]] {
    try mock.requests.dropFirst().map { request in
      let lastMessage = try #require(request.messages.last)
      return lastMessage.content
    }
  }

  private func containsReminder(_ content: [ContentBlock]) -> Bool {
    content.contains(where: {
      if case .text("Update your todos.") = $0 { true } else { false }
    })
  }

  @Test func noReminderWithoutActiveTodos() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      Self.bashToolUseResponse(id: "t1"),
      Self.bashToolUseResponse(id: "t2"),
      Self.bashToolUseResponse(id: "t3"),
      Self.bashToolUseResponse(id: "t4"),
      Self.endResponse
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    let userMsgs = try userMessages(from: mock)
    #expect(userMsgs.count == 4)
    for content in userMsgs {
      #expect(!containsReminder(content))
    }
  }

  @Test func reminderInjectedAtThreshold() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      Self.todoToolUseResponse(id: "t0"),  // creates pending todo, counter -> 0
      Self.bashToolUseResponse(id: "t1"),  // counter -> 1
      Self.bashToolUseResponse(id: "t2"),  // counter -> 2
      Self.bashToolUseResponse(id: "t3"),  // counter -> 3
      Self.endResponse
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    let userMsgs = try userMessages(from: mock)
    #expect(userMsgs.count == 4)
    // Turns 1–3 should NOT have the reminder
    #expect(!containsReminder(userMsgs[0]))
    #expect(!containsReminder(userMsgs[1]))
    #expect(!containsReminder(userMsgs[2]))
    // Turn 4 (counter == 3, active todos exist) should have the reminder
    #expect(containsReminder(userMsgs[3]))
    let lastBlock = try #require(userMsgs[3].last)
    #expect(lastBlock == .text("Update your todos."))
  }

  @Test func counterResetsOnTodoCall() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      Self.bashToolUseResponse(id: "t1"),   // counter -> 1
      Self.bashToolUseResponse(id: "t2"),   // counter -> 2
      Self.todoToolUseResponse(id: "t3"),   // counter -> 0
      Self.bashToolUseResponse(id: "t4"),   // counter -> 1
      Self.bashToolUseResponse(id: "t5"),   // counter -> 2
      Self.endResponse
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    let userMsgs = try userMessages(from: mock)
    #expect(userMsgs.count == 5)
    for content in userMsgs {
      #expect(!containsReminder(content))
    }
  }
}

// MARK: - Version

@Suite("Agent")
struct AgentTests {
  @Test func versionExists() {
    #expect(!Agent.version.isEmpty)
  }
}
