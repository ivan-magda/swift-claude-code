# swift-claude-code

Exploring the architecture of coding agents by rebuilding a Claude Code-style CLI from scratch in Swift.

![demo](demo.gif)

## Learning Series

A 9-part learning series covers the build on [ivanmagda.dev](https://ivanmagda.dev).

[Start the series →](https://ivanmagda.dev/posts/s00-bootstrapping-the-project)

## Why This Exists

Claude Code works better than most coding agents I've used, and I think the reason is restraint. I studied its tool surface and traced its loop to isolate which design choices do the work.

My working theory: **coding agents benefit more from a small set of excellent tools and a tight loop than from large orchestration layers.**

Claude Code ships few tools, and the ones it has are simple: a search tool, a file editor. They work well. The system trusts the model and skips the scaffolding most agents pile on.

This project rebuilds those mechanics in Swift, one stage at a time, to find out how little architecture the job needs.

## Hypothesis

This project tests a few specific ideas about coding agents:

- A small number of high-quality tools beats a large tool catalog
- The model should do the heavy lifting; orchestration stays thin
- Explicit task state improves reliability more than prompt-only planning
- Controlled context injection matters more than persistent memory
- Context compaction is a product feature, not a token optimization

Each stage isolates one mechanism so I can see what it enables.

## The Agent Loop

The whole thing boils down to one loop:

```swift
func run(query: String) async throws -> String {
    messages.append(.user(query))

    while true {
        let request = APIRequest(
            model: model, system: systemPrompt, messages: messages, tools: Self.toolDefinitions
        )
        let response = try await apiClient.createMessage(request)
        messages.append(Message(role: .assistant, content: response.content))

        guard response.stopReason == .toolUse else {
            return response.content.textContent
        }

        var results: [ContentBlock] = []
        for block in response.content {
            if case .toolUse(let id, let name, let input) = block {
                let output = await executeTool(name: name, input: input)
                results.append(.toolResult(toolUseId: id, content: output, isError: false))
            }
        }
        messages.append(Message(role: .user, content: results))
    }
}
```

The loop is fixed; the tools vary. Every stage adds entries to the tool handler dictionary and injection points before the API call, but the loop body itself stays identical.

## Roadmap

Git tags track progress. The roadmap has two phases: core mechanics first, then product-level features.

### Phase 1: Core Loop

The minimum viable agent: a loop and a small set of good tools.

| Stage | What It Adds                                                           | Tag                |
| ----- | ---------------------------------------------------------------------- | ------------------ |
| 00    | Bootstrap: SPM project, two-target layout, CI                          | `00-bootstrap`     |
| 01    | Agent loop + bash tool                                                 | `01-agent-loop`    |
| 02    | Tool dispatch: `read_file`, `write_file`, `edit_file` with path safety | `02-tool-dispatch` |
| 03    | Todo tracking with nag reminder injection                              | `03-todo-write`    |

### Phase 2: Product Mechanics

The features that make an agent feel like a usable product: context, memory management, and persistence.

| Stage | What It Adds                                                 | Tag                     |
| ----- | ------------------------------------------------------------ | ----------------------- |
| 04    | Subagents: recursive loop with fresh context                 | `04-subagents`          |
| 05    | Skill loading: `.md` files injected as tool results          | `05-skill-loading`      |
| 06    | Context compaction: 3-layer strategy (micro, auto, manual)   | `06-context-compaction` |
| 07    | Task system: file-based CRUD with dependency DAG             | `07-task-system`        |
| 08    | Background tasks: `Task {}` + actor-based notification queue | `08-background-tasks`   |

## Architecture

Two-target Swift Package Manager project:

**Core** is the library: API client, shell executor, agent loop, tools.

**CLI** is the entry point. The executable is named `agent`.

The agent talks to `POST https://api.anthropic.com/v1/messages` over raw HTTP, built on [AsyncHTTPClient](https://github.com/swift-server/async-http-client). It runs on macOS and Linux.

## Non-Goals

This project is **not**:

- A full Claude Code clone or drop-in replacement
- A general-purpose multi-agent framework
- Production-ready IDE tooling

It's a staged exploration of coding-agent architecture. The gaps are deliberate.

## Tech Stack

- **Swift 6.2** with strict concurrency
- **AsyncHTTPClient** (SwiftNIO-based) for cross-platform HTTP + streaming SSE
- **Foundation `Process`** for shell command execution
- macOS 10.15+ / Linux

## Getting Started

```bash
git clone https://github.com/ivan-magda/swift-claude-code.git
cd swift-claude-code

# Set up your API key and model
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY and MODEL_ID

swift build
swift run agent
```

## References

- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages): the one endpoint the agent talks to
- [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview): how tool definitions, `tool_use`, and `tool_result` work

## License

MIT
