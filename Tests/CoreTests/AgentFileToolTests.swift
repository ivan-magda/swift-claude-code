import Foundation
import Testing

@testable import Core

private func makeAgentInTempDir() throws -> (Agent, URL) {
  let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("agent-test-\(UUID().uuidString)")

  try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

  let agent = Agent(
    apiClient: MockAPIClient(),
    model: "test-model",
    systemPrompt: "test",
    workingDirectory: tempDir.path
  )

  return (agent, tempDir)
}

// MARK: - read_file

@Suite("read_file tool")
struct ReadFileToolTests {
  @Test func readsFileContent() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("test.txt")
    try "hello world".write(to: filePath, atomically: true, encoding: .utf8)

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": "test.txt"])
    )
    let output = try result.get()

    #expect(output.contains("hello world"))
  }

  @Test func respectsLineLimit() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("lines.txt")
    try "line1\nline2\nline3\nline4\nline5".write(
      to: filePath, atomically: true, encoding: .utf8
    )

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": "lines.txt", "limit": .int(2)])
    )
    let output = try result.get()

    #expect(output.contains("line1"))
    #expect(output.contains("line2"))
    #expect(output.contains("3 more lines"))
  }

  @Test func truncatesLargeContent() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("large.txt")
    try String(repeating: "x", count: 60_000).write(
      to: filePath, atomically: true, encoding: .utf8
    )

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": "large.txt"])
    )
    let output = try result.get()

    #expect(output.count == Limits.maxOutputSize)
  }

  @Test func fileNotFound() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": "nonexistent.txt"])
    )

    guard case .failure(.executionFailed) = result else {
      Issue.record("Expected executionFailed for missing file, got \(result)")
      return
    }
  }

  @Test func missingPathParameter() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "read_file",
      input: .object([:])
    )
    #expect(result == .failure(.missingParameter("path")))
  }
}

// MARK: - write_file

@Suite("write_file tool")
struct WriteFileToolTests {
  @Test func writesContent() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "write_file",
      input: .object(["path": "new.txt", "content": "written content"])
    )
    let output = try result.get()
    #expect(output.contains("Wrote"))

    let content = try String(
      contentsOfFile: tempDir.appendingPathComponent("new.txt").path,
      encoding: .utf8
    )
    #expect(content == "written content")
  }

  @Test func createsSubdirectories() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    _ = try await agent.executeTool(
      name: "write_file",
      input: .object(["path": "sub/dir/file.txt", "content": "nested"])
    ).get()

    let content = try String(
      contentsOfFile: tempDir.appendingPathComponent("sub/dir/file.txt").path,
      encoding: .utf8
    )
    #expect(content == "nested")
  }

  @Test func overwritesExisting() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("overwrite.txt")
    try "original".write(to: filePath, atomically: true, encoding: .utf8)

    _ = try await agent.executeTool(
      name: "write_file",
      input: .object(["path": "overwrite.txt", "content": "replaced"])
    ).get()

    let content = try String(contentsOfFile: filePath.path, encoding: .utf8)
    #expect(content == "replaced")
  }

  @Test func missingPath() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "write_file",
      input: .object(["content": "hello"])
    )
    #expect(result == .failure(.missingParameter("path")))
  }

  @Test func missingContent() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "write_file",
      input: .object(["path": "file.txt"])
    )
    #expect(result == .failure(.missingParameter("content")))
  }
}

// MARK: - edit_file

@Suite("edit_file tool")
struct EditFileToolTests {
  @Test func replacesText() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("edit.txt")
    try "foo bar baz".write(to: filePath, atomically: true, encoding: .utf8)

    let result = await agent.executeTool(
      name: "edit_file",
      input: .object(["path": "edit.txt", "old_text": "bar", "new_text": "qux"])
    )
    let output = try result.get()
    #expect(output.contains("Edited"))

    let content = try String(contentsOfFile: filePath.path, encoding: .utf8)
    #expect(content == "foo qux baz")
  }

  @Test func replacesOnlyFirstOccurrence() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("multi.txt")
    try "aaa bbb aaa".write(to: filePath, atomically: true, encoding: .utf8)

    _ = try await agent.executeTool(
      name: "edit_file",
      input: .object(["path": "multi.txt", "old_text": "aaa", "new_text": "ccc"])
    ).get()

    let content = try String(contentsOfFile: filePath.path, encoding: .utf8)
    #expect(content == "ccc bbb aaa")
  }

  @Test func textNotFound() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("edit2.txt")
    try "hello".write(to: filePath, atomically: true, encoding: .utf8)

    let result = await agent.executeTool(
      name: "edit_file",
      input: .object(["path": "edit2.txt", "old_text": "missing", "new_text": "x"])
    )
    #expect(result == .failure(.executionFailed("Text not found in edit2.txt")))
  }

  @Test func fileNotFound() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "edit_file",
      input: .object(["path": "missing.txt", "old_text": "a", "new_text": "b"])
    )
    guard case .failure(.executionFailed) = result else {
      Issue.record("Expected executionFailed for missing file, got \(result)")
      return
    }
  }

  @Test func missingOldText() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "edit_file",
      input: .object(["path": "f.txt", "new_text": "x"])
    )
    #expect(result == .failure(.missingParameter("old_text")))
  }
}

// MARK: - Path safety

@Suite("Path safety")
struct PathSafetyTests {
  @Test(
    "Blocks traversal",
    arguments: [
      ("read_file", JSONValue.object(["path": "../../../etc/passwd"])),
      ("write_file", JSONValue.object(["path": "../../escape.txt", "content": "pwned"])),
      (
        "edit_file",
        JSONValue.object([
          "path": "../../escape.txt", "old_text": "a", "new_text": "b"
        ])
      )
    ]
  )
  func blocksTraversal(toolName: String, input: JSONValue) async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(name: toolName, input: input)
    guard case .failure(.executionFailed(let message)) = result else {
      Issue.record("Expected path traversal error for \(toolName), got \(result)")
      return
    }

    #expect(message.contains("Path escapes workspace"))
  }

  @Test func absolutePathOutsideWorkspaceBlocked() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": "/etc/passwd"])
    )
    guard case .failure(.executionFailed(let message)) = result else {
      Issue.record("Expected path traversal error, got \(result)")
      return
    }
    #expect(message.contains("Path escapes workspace"))
  }

  @Test func absolutePathInsideWorkspaceAllowed() async throws {
    let (agent, tempDir) = try makeAgentInTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("abs.txt")
    try "absolute".write(to: filePath, atomically: true, encoding: .utf8)

    let result = await agent.executeTool(
      name: "read_file",
      input: .object(["path": .string(filePath.path)])
    )
    let output = try result.get()
    #expect(output == "absolute")
  }
}
