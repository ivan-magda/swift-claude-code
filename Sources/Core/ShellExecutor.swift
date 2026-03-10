@preconcurrency import Foundation

public struct ShellResult: Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32

  public var formatted: String {
    var output = stdout

    if !stderr.isEmpty {
      output += "\nSTDERR:\n\(stderr)"
    }

    if exitCode != 0 {
      output += "\n[exit code: \(exitCode)]"
    }

    if output.count > 50_000 {
      output = String(output.prefix(50_000))
    }

    return output.isEmpty ? "(no output)" : output
  }
}

public struct ShellExecutor: Sendable {
  private static let dangerousPatterns = [
    "rm -rf /", "sudo", "shutdown", "reboot", "> /dev/",
  ]

  public let workingDirectory: String

  public init(workingDirectory: String = ".") {
    self.workingDirectory = workingDirectory
  }

  /// Run a shell command and capture stdout, stderr, and exit code.
  /// Blocking calls occupy a cooperative pool thread — fine for sequential usage.
  public func execute(_ command: String) async throws -> ShellResult {
    if let blockedCommand = Self.dangerousPatterns.first(where: { command.contains($0) }) {
      return ShellResult(
        stdout: "",
        stderr: "Error: Dangerous command blocked (matched '\(blockedCommand)')",
        exitCode: 1
      )
    }

    let cwd = workingDirectory
    return try await Task.detached {
      let process = Process()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()

      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = ["-c", command]
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      process.currentDirectoryURL = URL(fileURLWithPath: cwd)

      try process.run()

      // Read pipe data BEFORE waitUntilExit() to avoid deadlock
      let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()

      return ShellResult(
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus
      )
    }
    .value
  }
}
