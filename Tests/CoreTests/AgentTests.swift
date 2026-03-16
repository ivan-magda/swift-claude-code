import Testing

@testable import Core

@Suite("Agent")
struct AgentTests {
  @Test func versionExists() {
    #expect(!Agent.version.isEmpty)
  }
}
