// swiftlint:disable file_length
import Foundation
import Testing

@testable import Core

// MARK: - Subagent

@Suite("Subagent")
struct SubagentTests {
  @Test func missingPromptReturnsError() async {
    let (agent, _) = makeAgent()
    let result = await agent.executeTool(
      name: "agent",
      input: .object([:])
    )
    #expect(result == .failure(.missingParameter("prompt")))
  }

  @Test func subagentSpawnsWithFreshMessages() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: returns final text
      makeResponse(content: [.text("subtask done")]),
      // Parent call 2: final answer after receiving subagent result
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "parent query")

    #expect(mock.requests.count == 3)

    // Subagent request (index 1) should have fresh messages with only the prompt
    let subagentMessages = mock.requests[1].messages
    #expect(subagentMessages.count == 1)
    #expect(subagentMessages[0].role == .user)
    #expect(subagentMessages[0].content == [.text("do subtask")])
  }

  @Test func subagentToolRestriction() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: returns final text
      makeResponse(content: [.text("subtask done")]),
      // Parent call 2: final answer
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "parent query")

    // Subagent request (index 1) should have only 4 tools (no agent, no todo)
    let subagentTools = mock.requests[1].tools ?? []
    let toolNames = Set(subagentTools.map(\.name))
    #expect(toolNames.count == 4)
    #expect(toolNames == ["bash", "read_file", "write_file", "edit_file"])
    #expect(!toolNames.contains("agent"))
    #expect(!toolNames.contains("todo"))
  }

  @Test func subagentResultFlowsToParent() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: returns final text
      makeResponse(content: [.text("subtask result text")]),
      // Parent call 2: final answer
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "parent query")

    // Parent's second request (index 2) should contain tool_result with subagent text
    let parentMessages = mock.requests[2].messages
    let lastMessage = try #require(parentMessages.last)
    #expect(lastMessage.role == .user)

    let hasSubagentResult = lastMessage.content.contains(where: {
      if case .toolResult(let id, let content, let isError) = $0 {
        return id == "t1" && content == "subtask result text" && !isError
      }
      return false
    })
    #expect(hasSubagentResult)
  }

  @Test func subagentIterationLimit() async throws {
    let mock = MockAPIClient()
    // Parent call 0: triggers agent tool_use
    var responses: [APIResponse] = [
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      )
    ]
    // Subagent calls 1–30: 30 bash tool_use responses (loop stops after 30 iterations)
    responses += toolUseResponses(count: 30)
    // Parent call after subagent completes (index 31)
    responses.append(makeResponse(content: [.text("parent done")]))
    mock.responses = responses
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "go")

    #expect(result == "parent done")

    // 1 parent + 30 subagent + 1 parent final = 32 total
    #expect(mock.requests.count == 32)

    // Parent's final request should contain tool_result with iteration limit message
    let parentMessages = mock.requests[31].messages
    let lastMessage = try #require(parentMessages.last)
    let hasLimitMessage = lastMessage.content.contains(where: {
      if case .toolResult(_, let content, _) = $0 {
        return content.contains("reached iteration limit")
      }
      return false
    })
    #expect(hasLimitMessage)
  }

  @Test func subagentOutputCap() async throws {
    let mock = MockAPIClient()
    let longText = String(repeating: "x", count: 60_000)
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: returns very long text
      makeResponse(content: [.text(longText)]),
      // Parent call 2: final answer
      makeResponse(content: [.text("done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    // Parent's final request should contain truncated tool_result
    let parentMessages = mock.requests[2].messages
    let lastMessage = try #require(parentMessages.last)
    let toolContent = lastMessage.content.compactMap { block -> String? in
      if case .toolResult(_, let content, _) = block {
        return content
      }
      return nil
    }.first
    let content = try #require(toolContent)
    #expect(content.count == Limits.maxOutputSize)
  }

  @Test func subagentEmptyOutputFallback() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: returns empty text
      makeResponse(content: []),
      // Parent call 2: final answer
      makeResponse(content: [.text("done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    // Parent's final request should contain "(no output)" tool_result
    let parentMessages = mock.requests[2].messages
    let lastMessage = try #require(parentMessages.last)
    let hasNoOutput = lastMessage.content.contains(where: {
      if case .toolResult(_, let content, _) = $0 {
        return content == "(no output)"
      }
      return false
    })
    #expect(hasNoOutput)
  }

  @Test func subagentErrorHandling() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      // Parent call 0: triggers agent tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent call 1: will throw simulatedError
      makeResponse(content: [.text("placeholder")]),
      // Parent call 2: final answer after receiving error
      makeResponse(content: [.text("recovered")])
    ]
    mock.errorAtIndices[1] = MockAPIClient.MockError.simulatedError
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "go")

    #expect(result == "recovered")

    // Parent's second request should contain tool_result with error message
    let parentMessages = mock.requests[2].messages
    let lastMessage = try #require(parentMessages.last)
    let hasErrorResult = lastMessage.content.contains(where: {
      if case .toolResult(_, let content, let isError) = $0 {
        return content.contains("Subagent failed:") && isError
      }
      return false
    })
    #expect(hasErrorResult)
  }
}

// MARK: - Subagent isolation

@Suite("Subagent isolation")
struct SubagentIsolationTests {
  @Test func subagentToolDispatchGuard() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent: API hallucinates an "agent" tool_use
      makeResponse(
        content: [
          .toolUse(id: "t2", name: "agent", input: .object(["prompt": "nested"]))
        ],
        stopReason: .toolUse
      ),
      makeResponse(content: [.text("subagent done")]),
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "go")

    #expect(result == "all done")

    let subagentMessages = mock.requests[2].messages
    let lastMessage = try #require(subagentMessages.last)
    let hasRejection = lastMessage.content.contains(where: {
      if case .toolResult(_, let content, let isError) = $0 {
        return content.contains("not allowed") && isError
      }
      return false
    })
    #expect(hasRejection)
  }

  @Test func subagentTodoToolDispatchGuard() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      // Subagent: API hallucinates a "todo" tool_use
      makeResponse(
        content: [
          .toolUse(
            id: "t2",
            name: "todo",
            input: .object([
              "items": .array([
                .object(["id": "1", "text": "task", "status": "pending"])
              ])
            ])
          )
        ],
        stopReason: .toolUse
      ),
      makeResponse(content: [.text("subagent done")]),
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    let result = try await agent.run(query: "go")

    #expect(result == "all done")

    let subagentMessages = mock.requests[2].messages
    let lastMessage = try #require(subagentMessages.last)
    let hasRejection = lastMessage.content.contains(where: {
      if case .toolResult(_, let content, let isError) = $0 {
        return content.contains("not allowed") && isError
      }
      return false
    })
    #expect(hasRejection)
  }

  @Test func noNagInSubagent() async throws {
    let mock = MockAPIClient()
    let todoInput: JSONValue = .object([
      "items": .array([.object(["id": "1", "text": "task", "status": "pending"])])
    ])
    mock.responses =
      [
        makeResponse(
          content: [.toolUse(id: "t0", name: "todo", input: todoInput)],
          stopReason: .toolUse
        ),
        makeResponse(
          content: [.toolUse(id: "t1", name: "agent", input: .object(["prompt": "do subtask"]))],
          stopReason: .toolUse
        )
      ]
      + toolUseResponses(count: 3)
      + [
        makeResponse(content: [.text("subtask done")]),
        makeResponse(content: [.text("all done")])
      ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "go")

    // Subagent requests with tool results are at indices 3, 4, 5
    for requestIndex in 3...5 {
      let messages = mock.requests[requestIndex].messages
      for message in messages where message.role == .user {
        let hasNag = message.content.contains(where: {
          if case .text("Update your todos.") = $0 { true } else { false }
        })
        #expect(!hasNag, "Subagent request \(requestIndex) should not contain nag reminder")
      }
    }
  }

  @Test func parentStateIsolation() async throws {
    let mock = MockAPIClient()
    mock.responses = [
      makeResponse(
        content: [
          .toolUse(
            id: "t1",
            name: "agent",
            input: .object(["prompt": "do subtask"])
          )
        ],
        stopReason: .toolUse
      ),
      makeResponse(
        content: [
          .toolUse(id: "s1", name: "bash", input: .object(["command": "echo internal"]))
        ],
        stopReason: .toolUse
      ),
      makeResponse(content: [.text("subtask done")]),
      makeResponse(content: [.text("all done")])
    ]
    let (agent, _) = makeAgent(mock: mock)

    _ = try await agent.run(query: "parent query")

    let parentMessages = mock.requests[3].messages
    #expect(parentMessages.count == 3)

    let hasBashToolUse = parentMessages.contains(where: { message in
      message.content.contains(where: {
        if case .toolUse(_, let name, _) = $0 {
          return name == "bash"
        }
        return false
      })
    })
    #expect(!hasBashToolUse, "Parent messages should not contain subagent's internal tool calls")

    let lastMessage = try #require(parentMessages.last)
    let hasSubagentResult = lastMessage.content.contains(where: {
      if case .toolResult(let id, let content, _) = $0 {
        return id == "t1" && content == "subtask done"
      }
      return false
    })
    #expect(hasSubagentResult)
  }
}
