import Core
import Foundation

@main
struct SwiftClaudeCode {
  static func main() async throws {
    print("\(ANSIColor.bold)swift-claude-code\(ANSIColor.reset) v\(Agent.version)")
    print("\(ANSIColor.dim)A Claude Code-like agent built from scratch in Swift\(ANSIColor.reset)")
    print()

    let dotEnv = parseDotEnv(at: FileManager.default.currentDirectoryPath + "/.env")

    guard let apiKey = resolveEnv("ANTHROPIC_API_KEY", dotEnv: dotEnv) else {
      fatalError("ANTHROPIC_API_KEY is required. Set it in your environment or in a .env file.")
    }
    guard let model = resolveEnv("MODEL_ID", dotEnv: dotEnv) else {
      fatalError("MODEL_ID is required. Set it in your environment or in a .env file.")
    }
    let cwd = FileManager.default.currentDirectoryPath

    let agent = Agent(
      apiClient: APIClient(apiKey: apiKey),
      model: model,
      workingDirectory: cwd
    )

    print("\(ANSIColor.dim)Model: \(model)\(ANSIColor.reset)")
    print("\(ANSIColor.dim)Working directory: \(cwd)\(ANSIColor.reset)")
    print("\(ANSIColor.dim)Type 'exit' or Ctrl+C to quit.\(ANSIColor.reset)")
    print()

    // REPL loop
    while true {
      print("\(ANSIColor.cyan)\(ANSIColor.bold)>\(ANSIColor.reset) ", terminator: "")
      guard let input = readLine(strippingNewline: true) else {
        break
      }

      let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        continue
      }
      if ["exit", "quit", "q"].contains(trimmed.lowercased()) {
        break
      }

      do {
        _ = try await agent.run(query: trimmed)
      } catch {
        print("\(ANSIColor.red)Error: \(error)\(ANSIColor.reset)")
      }

      print()
    }
  }
}

// MARK: - Environment

extension SwiftClaudeCode {
  private static func resolveEnv(_ key: String, dotEnv: [String: String]) -> String? {
    if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
      return value
    }
    return dotEnv[key]
  }

  private static func parseDotEnv(at path: String) -> [String: String] {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
      return [:]
    }

    var result: [String: String] = [:]
    for line in contents.split(separator: "\n") {
      if line.hasPrefix("#") || line.isEmpty {
        continue
      }

      let parts = line.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else {
        continue
      }

      result[String(parts[0])] = String(parts[1])
    }

    return result
  }
}
