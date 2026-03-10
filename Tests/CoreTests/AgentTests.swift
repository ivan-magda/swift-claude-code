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

  @Test func validCommandReturnsOutput() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "bash",
      input: .object(["command": "echo hello"])
    )
    guard case .success(let output) = result else {
      Issue.record("Expected .success, got \(result)")
      return
    }
    #expect(output.contains("hello"))
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
          .toolUse(id: "t1", name: "bash", input: .object(["command": "echo hi"])),
        ],
        stopReason: .toolUse
      ),
      // Second response: final answer after seeing tool result
      makeResponse(content: [.text("done")]),
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

// MARK: - Version

@Suite("Agent")
struct AgentTests {
  @Test func versionExists() {
    #expect(Agent.version == "0.1.0")
  }
}
