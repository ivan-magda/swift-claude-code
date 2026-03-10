import Foundation

public final class Agent {
  public static let version = "0.1.0"

  private let apiClient: any APIClientProtocol
  private let model: String
  private let systemPrompt: String
  private let shellExecutor: ShellExecutor
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
    self.shellExecutor = ShellExecutor(workingDirectory: workingDirectory)
  }

  // MARK: - Agent loop

  public func run(query: String) async throws -> String {
    messages.append(.user(query))

    while true {
      let request = APIRequest(
        model: model,
        maxTokens: 4096,
        system: systemPrompt,
        messages: messages,
        tools: [Self.bashToolDefinition]
      )

      let response = try await apiClient.createMessage(request: request)
      messages.append(Message(role: .assistant, content: response.content))

      for block in response.content {
        if case .text(let text) = block {
          print("\(ANSIColor.cyan)\(text)\(ANSIColor.reset)")
        }
      }

      guard response.stopReason == .toolUse else {
        return response.content.textContent
      }

      var results: [ContentBlock] = []
      for block in response.content {
        if case .toolUse(let id, let name, let input) = block {
          printToolCall(name: name, input: input)
          let toolResult = await executeTool(name: name, input: input)

          switch toolResult {
          case .success(let output):
            print("\(ANSIColor.dim)\(String(output.prefix(200)))\(ANSIColor.reset)")
            results.append(.toolResult(toolUseId: id, content: output, isError: false))
          case .failure(let error):
            let message = "\(error)"
            print("\(ANSIColor.red)\(message)\(ANSIColor.reset)")
            results.append(.toolResult(toolUseId: id, content: message, isError: true))
          }
        }
      }

      messages.append(Message(role: .user, content: results))
    }
  }

  public static func buildSystemPrompt(cwd: String) -> String {
    """
    You are a coding agent at \(cwd). You help the user by executing \
    shell commands to explore the filesystem, read and write files, run programs, \
    and accomplish tasks.

    Guidelines:
    - Use the bash tool to execute commands
    - Always check the result of commands before proceeding
    - If a command fails, try to understand why and fix it
    - Be concise in your explanations
    - When editing files, show the relevant changes
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

  private static let bashToolDefinition = ToolDefinition(
    name: "bash",
    description: "Run a shell command and return its output.",
    inputSchema: .object([
      "type": "object",
      "properties": .object([
        "command": .object([
          "type": "string",
          "description": "The shell command to execute",
        ])
      ]),
      "required": .array(["command"]),
    ])
  )

  func executeTool(name: String, input: JSONValue) async -> Result<String, ToolError> {
    guard name == "bash" else {
      return .failure(.unknownTool(name))
    }

    guard let command = input["command"]?.stringValue else {
      return .failure(.missingParameter("command"))
    }

    do {
      let result = try await shellExecutor.execute(command)
      return .success(result.formatted)
    } catch {
      return .failure(.executionFailed(error.localizedDescription))
    }
  }

  private func printToolCall(name: String, input: JSONValue) {
    if let command = input["command"]?.stringValue {
      print("\(ANSIColor.yellow)$ \(command)\(ANSIColor.reset)")
    } else {
      print("\(ANSIColor.yellow)⚡ \(name)\(ANSIColor.reset)")
    }
  }
}
