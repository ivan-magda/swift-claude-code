// swiftlint:disable file_length
import Foundation

public enum Limits {
  public static let maxOutputSize = 50_000
  public static let defaultMaxTokens = 4096
  static let logPreviewLength = 200
}

public final class Agent {
  public static let version = "0.4.0"

  private static let todoReminderThreshold = 3

  private let apiClient: any APIClientProtocol
  private let model: String
  private let systemPrompt: String
  private let workingDirectory: String

  private let shellExecutor: ShellExecutor
  private let todoManager = TodoManager()

  private var messages: [Message] = []

  public init(
    apiClient: APIClientProtocol,
    model: String,
    systemPrompt: String? = nil,
    workingDirectory: String = "."
  ) {
    self.apiClient = apiClient
    self.model = model
    self.systemPrompt = systemPrompt ?? Self.buildSystemPrompt(cwd: workingDirectory)
    self.workingDirectory = workingDirectory
    self.shellExecutor = ShellExecutor(workingDirectory: workingDirectory)
  }

  // MARK: - Agent loop

  public func run(query: String) async throws -> String {
    messages.append(.user(query))

    let result = try await agentLoop(initialMessages: messages, config: .default)
    messages = result.messages

    return result.text
  }

  private func agentLoop(
    initialMessages: [Message],
    config: LoopConfig
  ) async throws -> (text: String, messages: [Message]) {
    var messages = initialMessages
    var turnsWithoutTodo = 0
    var iteration = 0
    var lastAssistantText = ""

    let allowedTools = Set(config.tools.map(\.name))

    while true {
      try Task.checkCancellation()

      iteration += 1
      if iteration > config.maxIterations {
        return (lastAssistantText + "\n(\(config.label) reached iteration limit)", messages)
      }

      let request = APIRequest(
        model: model,
        maxTokens: Limits.defaultMaxTokens,
        system: systemPrompt,
        messages: messages,
        tools: config.tools
      )

      let response = try await apiClient.createMessage(request: request)
      messages.append(Message(role: .assistant, content: response.content))
      lastAssistantText = response.content.textContent

      for block in response.content {
        if case .text(let text) = block {
          print("[\(config.label)] \(ANSIColor.cyan)\(text)\(ANSIColor.reset)")
        }
      }

      guard response.stopReason == .toolUse else {
        return (response.content.textContent, messages)
      }

      let (results, didUseTodo) = await processToolUses(
        response: response,
        allowedTools: allowedTools,
        label: config.label
      )

      var toolResults = results
      if config.enableNag {
        turnsWithoutTodo = didUseTodo ? 0 : turnsWithoutTodo + 1
        if turnsWithoutTodo >= Self.todoReminderThreshold && todoManager.hasOpenItems() {
          toolResults.append(.text("Update your todos."))
        }
      }

      messages.append(Message(role: .user, content: toolResults))
    }
  }

  public static func buildSystemPrompt(cwd: String) -> String {
    """
    You are a coding agent at \(cwd). Use tools to solve tasks. \
    Act, don't explain.

    - Prefer read_file/write_file/edit_file over bash for file operations
    - Always check tool results before proceeding
    - Use the todo tool to plan multi-step tasks. Mark in_progress before starting, completed when done.
    """
  }
}

// MARK: - Tools

extension Agent {
  public enum ToolError: Error, Equatable {
    case unknownTool(String)
    case missingParameter(String)
    case executionFailed(String)
  }

  static let toolDefinitions: [ToolDefinition] = [
    ToolDefinition(
      name: "bash",
      description: "Run a shell command.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "command": .object([
            "type": "string",
            "description": "The shell command to execute"
          ])
        ]),
        "required": .array(["command"])
      ])
    ),
    ToolDefinition(
      name: "read_file",
      description: "Read file contents.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "path": .object([
            "type": "string",
            "description": "The file path to read"
          ]),
          "limit": .object([
            "type": "integer",
            "description": "Maximum number of lines to read"
          ])
        ]),
        "required": .array(["path"])
      ])
    ),
    ToolDefinition(
      name: "write_file",
      description: "Write content to a file.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "path": .object([
            "type": "string",
            "description": "The file path to write"
          ]),
          "content": .object([
            "type": "string",
            "description": "The content to write"
          ])
        ]),
        "required": .array(["path", "content"])
      ])
    ),
    ToolDefinition(
      name: "edit_file",
      description: "Replace exact text in a file.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "path": .object([
            "type": "string",
            "description": "The file path to edit"
          ]),
          "old_text": .object([
            "type": "string",
            "description": "The exact text to find and replace"
          ]),
          "new_text": .object([
            "type": "string",
            "description": "The replacement text"
          ])
        ]),
        "required": .array(["path", "old_text", "new_text"])
      ])
    ),
    ToolDefinition(
      name: "todo",
      description: "Update task list. Track progress on multi-step tasks.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "items": .object([
            "type": "array",
            "items": .object([
              "type": "object",
              "properties": .object([
                "id": .object(["type": "string"]),
                "text": .object(["type": "string"]),
                "status": .object([
                  "type": "string",
                  "enum": .array(["pending", "in_progress", "completed"])
                ])
              ]),
              "required": .array(["id", "text", "status"])
            ])
          ])
        ]),
        "required": .array(["items"])
      ])
    ),
    ToolDefinition(
      name: "agent",
      description: "Spawn a subagent to handle a complex subtask independently.",
      inputSchema: .object([
        "type": "object",
        "properties": .object([
          "prompt": .object([
            "type": "string",
            "description": "The task for the subagent to complete"
          ])
        ]),
        "required": .array(["prompt"])
      ])
    )
  ]

  func executeTool(name: String, input: JSONValue) async -> Result<String, ToolError> {
    let handlers = [
      "bash": executeBash,
      "read_file": executeReadFile,
      "write_file": executeWriteFile,
      "edit_file": executeEditFile,
      "todo": executeTodo,
      "agent": executeAgent
    ]

    guard let handler = handlers[name] else {
      return .failure(.unknownTool(name))
    }

    return await handler(input)
  }

  // MARK: - Handlers

  private func executeBash(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let command = input["command"]?.stringValue else {
      return .failure(.missingParameter("command"))
    }

    do {
      let result = try await shellExecutor.execute(command)
      return .success(result.formatted)
    } catch {
      return .failure(.executionFailed("\(error)"))
    }
  }

  private func executeReadFile(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let path = input["path"]?.stringValue else {
      return .failure(.missingParameter("path"))
    }

    switch resolveSafePath(path) {
    case .failure(let error):
      return .failure(error)
    case .success(let resolvedPath):
      do {
        let text = try String(contentsOfFile: resolvedPath, encoding: .utf8)

        let lines = text.components(separatedBy: "\n")
        var output: String

        if let limit = input["limit"]?.intValue, limit < lines.count {
          output =
            lines.prefix(limit).joined(separator: "\n")
            + "\n... (\(lines.count - limit) more lines)"
        } else {
          output = text
        }

        if output.count > Limits.maxOutputSize {
          output = String(output.prefix(Limits.maxOutputSize))
        }

        return .success(output)
      } catch {
        return .failure(.executionFailed("\(error)"))
      }
    }
  }

  private func executeWriteFile(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let path = input["path"]?.stringValue else {
      return .failure(.missingParameter("path"))
    }

    guard let content = input["content"]?.stringValue else {
      return .failure(.missingParameter("content"))
    }

    switch resolveSafePath(path) {
    case .failure(let error):
      return .failure(error)
    case .success(let resolvedPath):
      do {
        let fileURL = URL(fileURLWithPath: resolvedPath)

        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)

        return .success("Wrote \(content.utf8.count) bytes to \(path)")
      } catch {
        return .failure(.executionFailed("\(error)"))
      }
    }
  }

  private func executeEditFile(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let path = input["path"]?.stringValue else {
      return .failure(.missingParameter("path"))
    }

    guard let oldText = input["old_text"]?.stringValue else {
      return .failure(.missingParameter("old_text"))
    }

    guard let newText = input["new_text"]?.stringValue else {
      return .failure(.missingParameter("new_text"))
    }

    switch resolveSafePath(path) {
    case .failure(let error):
      return .failure(error)
    case .success(let resolvedPath):
      do {
        var content = try String(contentsOfFile: resolvedPath, encoding: .utf8)

        guard let range = content.range(of: oldText) else {
          return .failure(.executionFailed("Text not found in \(path)"))
        }

        content.replaceSubrange(range, with: newText)
        try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)

        return .success("Edited \(path)")
      } catch {
        return .failure(.executionFailed("\(error)"))
      }
    }
  }

  private func executeAgent(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let prompt = input["prompt"]?.stringValue else {
      return .failure(.missingParameter("prompt"))
    }

    do {
      let result = try await agentLoop(
        initialMessages: [Message.user(prompt)],
        config: .subagent
      )
      var output = result.text

      if output.isEmpty {
        output = "(no output)"
      } else if output.count > Limits.maxOutputSize {
        output = String(output.prefix(Limits.maxOutputSize))
      }

      return .success(output)
    } catch {
      return .failure(.executionFailed("Subagent failed: \(error)"))
    }
  }

  private func executeTodo(_ input: JSONValue) async -> Result<String, ToolError> {
    guard let itemsArray = input["items"]?.arrayValue else {
      return .failure(.missingParameter("items"))
    }

    var todoItems: [TodoItem] = []
    for element in itemsArray {
      guard let id = element["id"]?.stringValue else {
        return .failure(.missingParameter("items[].id"))
      }
      guard let text = element["text"]?.stringValue else {
        return .failure(.missingParameter("items[].text"))
      }
      guard let statusString = element["status"]?.stringValue else {
        return .failure(.missingParameter("items[].status"))
      }
      guard let status = TodoStatus(rawValue: statusString) else {
        return .failure(.executionFailed("Invalid status '\(statusString)' for item \(id)"))
      }
      todoItems.append(TodoItem(id: id, text: text, status: status))
    }

    do {
      try todoManager.update(items: todoItems)
      return .success(todoManager.render())
    } catch {
      return .failure(.executionFailed("\(error)"))
    }
  }

  // MARK: Helpers

  private func processToolUses(
    response: APIResponse,
    allowedTools: Set<String>,
    label: String
  ) async -> (results: [ContentBlock], didUseTodo: Bool) {
    var results: [ContentBlock] = []
    var didUseTodo = false

    for case .toolUse(let id, let name, let input) in response.content {
      guard allowedTools.contains(name) else {
        let message = "Tool '\(name)' is not allowed in this context"
        print("[\(label)] \(ANSIColor.red)\(message)\(ANSIColor.reset)")
        results.append(.toolResult(toolUseId: id, content: message, isError: true))
        continue
      }

      printToolCall(name: name, input: input, label: label)
      let toolResult = await executeTool(name: name, input: input)

      if name == "todo" {
        didUseTodo = true
      }

      switch toolResult {
      case .success(let output):
        print("[\(label)] \(ANSIColor.dim)\(String(output.prefix(Limits.logPreviewLength)))\(ANSIColor.reset)")
        results.append(.toolResult(toolUseId: id, content: output, isError: false))
      case .failure(let error):
        let message = "\(error)"
        print("[\(label)] \(ANSIColor.red)\(message)\(ANSIColor.reset)")
        results.append(.toolResult(toolUseId: id, content: message, isError: true))
      }
    }

    return (results, didUseTodo)
  }

  private func resolveSafePath(_ relativePath: String) -> Result<String, ToolError> {
    let workDirURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    let resolvedWorkDir = workDirURL.standardized

    let fullURL =
      if relativePath.hasPrefix("/") {
        URL(fileURLWithPath: relativePath).standardized
      } else {
        workDirURL.appendingPathComponent(relativePath).standardized
      }

    guard
      fullURL.path.hasPrefix(resolvedWorkDir.path + "/") || fullURL.path == resolvedWorkDir.path
    else {
      return .failure(.executionFailed("Path escapes workspace: \(relativePath)"))
    }

    return .success(fullURL.path)
  }

  private func printToolCall(name: String, input: JSONValue, label: String) {
    if name == "bash", let command = input["command"]?.stringValue {
      print("[\(label)] \(ANSIColor.yellow)$ \(command)\(ANSIColor.reset)")
    } else if let path = input["path"]?.stringValue {
      print("[\(label)] \(ANSIColor.yellow)> \(name): \(path)\(ANSIColor.reset)")
    } else {
      print("[\(label)] \(ANSIColor.yellow)> \(name)\(ANSIColor.reset)")
    }
  }
}

// MARK: - Configuration

extension Agent {
  fileprivate struct LoopConfig {
    let tools: [ToolDefinition]
    let maxIterations: Int
    let enableNag: Bool
    let label: String

    static let `default` = LoopConfig(
      tools: Agent.toolDefinitions,
      maxIterations: .max,
      enableNag: true,
      label: "agent"
    )

    static let subagent = LoopConfig(
      tools: Agent.toolDefinitions.filter { $0.name != "agent" && $0.name != "todo" },
      maxIterations: 30,
      enableNag: false,
      label: "subagent"
    )
  }
}
