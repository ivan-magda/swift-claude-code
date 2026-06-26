import Foundation

public struct SkillLoader: Sendable {
  public struct Skill: Sendable {
    public let name: String
    public let description: String
    public let body: String
  }

  private let skills: [String: Skill]

  public init(directory: String) {
    let fileManager = FileManager.default
    var loadedSkills: [String: Skill] = [:]

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      self.skills = [:]
      return
    }

    let contents = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
    for entry in contents {
      // Validate entry name to prevent path traversal attacks
      // Reject entries with path separators or parent directory references
      guard !entry.contains("/"),
            !entry.contains("\\"),
            !entry.hasPrefix(".")
      else {
        continue
      }

      let skillFile = "\(directory)/\(entry)/SKILL.md"
      guard fileManager.fileExists(atPath: skillFile),
        let text = try? String(contentsOfFile: skillFile, encoding: .utf8)
      else {
        continue
      }

      let (meta, body) = Self.parseFrontmatter(text)
      let skillName = meta["name"] ?? entry
      guard let description = meta["description"] else {
        continue
      }

      loadedSkills[skillName] = Skill(
        name: skillName,
        description: description,
        body: body.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    self.skills = loadedSkills
  }

  public var isEmpty: Bool { skills.isEmpty }

  public var descriptions: String {
    guard !skills.isEmpty else {
      return ""
    }

    return skills.values
      .sorted { $0.name < $1.name }
      .map { "  - \($0.name): \($0.description)" }
      .joined(separator: "\n")
  }

  public func content(for name: String) -> String {
    if let skill = skills[name] {
      return "<skill name=\"\(name)\">\n\(skill.body)\n</skill>"
    }

    if skills.isEmpty {
      return "Unknown skill '\(name)'. No skills are available."
    }

    let available = skills.keys.sorted().joined(separator: ", ")
    return "Unknown skill '\(name)'. Available skills: \(available)"
  }

  private static func parseFrontmatter(_ text: String) -> (meta: [String: String], body: String) {
    let lines = text.components(separatedBy: "\n")

    guard let firstLine = lines.first,
      firstLine.trimmingCharacters(in: .whitespaces) == "---"
    else {
      return (meta: [:], body: text)
    }

    var meta: [String: String] = [:]
    var closingIndex: Int?

    for index in 1..<lines.count {
      let line = lines[index]
      if line.trimmingCharacters(in: .whitespaces) == "---" {
        closingIndex = index
        break
      }

      if let colonRange = line.range(of: ":") {
        let key = String(line[line.startIndex..<colonRange.lowerBound])
          .trimmingCharacters(in: .whitespaces)
        let value = String(line[colonRange.upperBound...])
          .trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
          meta[key] = value
        }
      }
    }

    guard let closing = closingIndex else {
      return (meta: [:], body: text)
    }

    let bodyLines = Array(lines[(closing + 1)...])
    let body = bodyLines.joined(separator: "\n")
    return (meta: meta, body: body)
  }
}
