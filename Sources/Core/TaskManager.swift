import Foundation

public enum TaskStatus: String, Sendable, Equatable, Codable {
  case pending
  case inProgress = "in_progress"
  case completed

  public var marker: String {
    switch self {
    case .pending: "[ ]"
    case .inProgress: "[>]"
    case .completed: "[x]"
    }
  }
}

public struct AgentTask: Sendable, Equatable, Codable {
  public let id: Int
  public let subject: String
  public let description: String
  public fileprivate(set) var status: TaskStatus
  public fileprivate(set) var blockedBy: [Int]
  public fileprivate(set) var blocks: [Int]
  public let owner: String

  public init(
    id: Int,
    subject: String,
    description: String = "",
    status: TaskStatus = .pending,
    blockedBy: [Int] = [],
    blocks: [Int] = [],
    owner: String = ""
  ) {
    self.id = id
    self.subject = subject
    self.description = description
    self.status = status
    self.blockedBy = blockedBy
    self.blocks = blocks
    self.owner = owner
  }
}

public final class TaskManager {
  private let directory: String

  private var nextId: Int

  public enum TaskError: Error, Equatable, Sendable {
    case taskNotFound(Int)
    case invalidStatus(String)
    case selfReferentialDependency(Int)
  }

  public init(directory: String) {
    self.directory = directory

    let fm = FileManager.default
    if !fm.fileExists(atPath: directory) {
      try? fm.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true
      )
    }

    self.nextId = Self.maxId(in: directory) + 1
  }

  // MARK: - Public API

  public func create(subject: String, description: String = "") throws -> String {
    let task = AgentTask(id: nextId, subject: subject, description: description)
    let json = try saveAndSerialize(task)
    nextId += 1
    return json
  }

  public func get(taskId: Int) throws -> String {
    let task = try load(taskId)
    return jsonString(for: task)
  }

  public func update(
    taskId: Int,
    status: String? = nil,
    addBlockedBy: [Int] = [],
    addBlocks: [Int] = []
  ) throws -> String {
    var task = try load(taskId)

    if let status {
      guard let newStatus = TaskStatus(rawValue: status) else {
        throw TaskError.invalidStatus(status)
      }
      task.status = newStatus
    }

    try applyBlockedBy(addBlockedBy, to: &task)
    try applyBlocks(addBlocks, to: &task)
    let json = try saveAndSerialize(task)

    if task.status == .completed {
      removeCompletedDependency(for: task.id)
    }

    return json
  }

  private func applyBlockedBy(_ ids: [Int], to task: inout AgentTask) throws {
    for blockerId in ids where blockerId == task.id {
      throw TaskError.selfReferentialDependency(task.id)
    }

    for blockerId in ids {
      if !task.blockedBy.contains(blockerId) {
        task.blockedBy.append(blockerId)
      }

      // Load blocker task and maintain bidirectional relationship
      // Throw error if blocker doesn't exist to prevent asymmetric state
      guard var blocker = try? load(blockerId) else {
        // Revert the blockedBy addition since blocker doesn't exist
        if let index = task.blockedBy.firstIndex(of: blockerId) {
          task.blockedBy.remove(at: index)
        }
        throw TaskError.taskNotFound(blockerId)
      }

      if !blocker.blocks.contains(task.id) {
        blocker.blocks.append(task.id)
        try? save(blocker)
      }
    }
  }

  private func applyBlocks(_ ids: [Int], to task: inout AgentTask) throws {
    for dependentId in ids where dependentId == task.id {
      throw TaskError.selfReferentialDependency(task.id)
    }

    for dependentId in ids {
      if !task.blocks.contains(dependentId) {
        task.blocks.append(dependentId)
      }

      // Load dependent task and maintain bidirectional relationship
      // Throw error if dependent doesn't exist to prevent asymmetric state
      guard var dependent = try? load(dependentId) else {
        // Revert the blocks addition since dependent doesn't exist
        if let index = task.blocks.firstIndex(of: dependentId) {
          task.blocks.remove(at: index)
        }
        throw TaskError.taskNotFound(dependentId)
      }

      if !dependent.blockedBy.contains(task.id) {
        dependent.blockedBy.append(task.id)
        try? save(dependent)
      }
    }
  }

  public func listAll() -> String {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
      return "No tasks."
    }

    let taskFiles = files.filter {
      $0.hasPrefix("task_") && $0.hasSuffix(".json")
    }.sorted { lhs, rhs in
      (Self.parseId(from: lhs) ?? 0) < (Self.parseId(from: rhs) ?? 0)
    }

    if taskFiles.isEmpty {
      return "No tasks."
    }

    var lines: [String] = []
    for file in taskFiles {
      let path = (directory as NSString).appendingPathComponent(file)

      guard
        let data = fm.contents(atPath: path),
        let task = try? JSONDecoder().decode(AgentTask.self, from: data)
      else {
        continue
      }

      var line = "\(task.status.marker) \(task.id): \(task.subject)"
      if !task.blockedBy.isEmpty {
        let blockers = task.blockedBy.map(String.init).joined(separator: ", ")
        line += " (blocked by: \(blockers))"
      }
      lines.append(line)
    }

    if lines.isEmpty {
      return "No tasks."
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Dependency Resolution

  private func removeCompletedDependency(for completedId: Int) {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
      return
    }

    for file in files where file.hasPrefix("task_") && file.hasSuffix(".json") {
      let path = (directory as NSString).appendingPathComponent(file)
      guard
        let data = fm.contents(atPath: path),
        var task = try? JSONDecoder().decode(AgentTask.self, from: data)
      else {
        continue
      }

      if task.blockedBy.contains(completedId) {
        task.blockedBy.removeAll { $0 == completedId }
        try? save(task)
      }
    }
  }

  // MARK: - Private Helpers

  private func load(_ taskId: Int) throws -> AgentTask {
    let path = filePath(for: taskId)
    guard let data = FileManager.default.contents(atPath: path) else {
      throw TaskError.taskNotFound(taskId)
    }
    return try JSONDecoder().decode(AgentTask.self, from: data)
  }

  private func save(_ task: AgentTask) throws {
    let data = try encode(task)
    let path = filePath(for: task.id)
    try data.write(to: URL(fileURLWithPath: path))
  }

  private func saveAndSerialize(_ task: AgentTask) throws -> String {
    let data = try encode(task)
    let path = filePath(for: task.id)
    try data.write(to: URL(fileURLWithPath: path))
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  private func encode(_ task: AgentTask) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(task)
  }

  private func filePath(for taskId: Int) -> String {
    (directory as NSString).appendingPathComponent("task_\(taskId).json")
  }

  private static func maxId(in directory: String) -> Int {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
      return 0
    }
    return files.compactMap { parseId(from: $0) }.max() ?? 0
  }

  private static func parseId(from filename: String) -> Int? {
    guard
      filename.hasPrefix("task_"),
      filename.hasSuffix(".json")
    else {
      return nil
    }
    let stem = filename.dropFirst(5).dropLast(5)
    return Int(stem)
  }

  private func jsonString(for task: AgentTask) -> String {
    guard
      let data = try? encode(task),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }
}
