import Foundation

public enum TodoStatus: String, Sendable, Equatable, Codable {
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

public struct TodoItem: Sendable, Equatable, Codable {
  public let id: String
  public let text: String
  public let status: TodoStatus

  public init(id: String, text: String, status: TodoStatus) {
    self.id = id
    self.text = text
    self.status = status
  }
}

public final class TodoManager {
  public static let maxItems = 20
  public private(set) var items: [TodoItem] = []

  public enum ValidationError: Error, Equatable, Sendable {
    case tooManyItems
    case emptyText(String)
    case multipleInProgress
  }

  public init() {}

  public func update(items: [TodoItem]) throws {
    if items.count > Self.maxItems {
      throw ValidationError.tooManyItems
    }

    for item in items where item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw ValidationError.emptyText(item.id)
    }

    let inProgressCount = items.filter { $0.status == .inProgress }.count
    if inProgressCount > 1 {
      throw ValidationError.multipleInProgress
    }

    self.items = items
  }

  public func render() -> String {
    if items.isEmpty {
      return "No todos."
    }

    let completedCount = items.filter { $0.status == .completed }.count
    var lines = items.map { "\($0.status.marker) \($0.text)" }
    lines.append("(\(completedCount)/\(items.count) completed)")

    return lines.joined(separator: "\n")
  }

  public func hasOpenItems() -> Bool {
    items.contains { $0.status != .completed }
  }
}
