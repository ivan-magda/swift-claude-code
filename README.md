# swift-claude-code

Exploring the architecture of coding agents by rebuilding a Claude Code-style CLI from scratch in Swift.

> **Current progress:** Stage 02 of 12 — tool dispatch with `read_file`, `write_file`, `edit_file`

![demo](demo.gif)

## Why This Exists

Claude Code feels unusually effective compared to other coding agents, and I suspect most of it comes from architectural restraint rather than architectural complexity. I studied the tool surface, traced the interaction loop, and tried to isolate which design choices actually matter.

My working theory: **coding agents benefit more from a small set of excellent tools and tight loop design than from large orchestration layers.**

Claude Code doesn't have many tools. The tools it does have are simple: a search tool, a file editing tool. But those tools are really good. And the system leans on the model far more than most agent implementations — less scaffolding, more trust in the LLM to do the heavy lifting.

This project tests that idea by rebuilding the core mechanics from scratch in Swift, one stage at a time, to see how little architecture you actually need.

## Hypothesis

This project tests a few specific ideas about coding agents:

- A small number of high-quality tools beats a large tool catalog
- The model should do most of the heavy lifting — thin orchestration, not thick
- Explicit task state improves reliability more than prompt-only planning
- Controlled context injection matters more than persistent memory
- Context compaction is a product feature, not just a token optimization

Each stage is designed to isolate one mechanism and see what it enables.

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

The loop is the invariant. Tools are the variable. Every stage adds entries to the tool handler dictionary and injection points before the API call, but the loop body itself never changes.

## Roadmap

Progress is tracked via git tags. The roadmap is split into three phases — core mechanics first, then product-level features, then experimental multi-agent systems.

### Phase 1 — Core Loop

The minimum viable agent: a loop and a small set of good tools.

| Stage  | What It Adds                                                           | Tag                |
| ------ | ---------------------------------------------------------------------- | ------------------ |
| **00** | Bootstrap: SPM project, two-target layout, CI                          | `00-bootstrap`     |
| **01** | Agent loop + bash tool                                                 | `01-agent-loop`    |
| **02** | Tool dispatch: `read_file`, `write_file`, `edit_file` with path safety | `02-tool-dispatch` |
| 03     | Todo tracking with nag reminder injection                              | —                  |

### Phase 2 — Product Mechanics

The features that make an agent feel like a usable product: context, memory management, and persistence.

| Stage | What It Adds                                                 | Tag |
| ----- | ------------------------------------------------------------ | --- |
| 04    | Subagents: recursive loop with fresh context                 | —   |
| 05    | Skill loading: `.md` files injected as tool results          | —   |
| 06    | Context compaction: 3-layer strategy (micro, auto, manual)   | —   |
| 07    | Task system: file-based CRUD with dependency DAG             | —   |
| 08    | Background tasks: `Task {}` + actor-based notification queue | —   |

### Phase 3 — Experimental

Multi-agent coordination. These stages explore ideas beyond the core product loop.

| Stage | What It Adds                                          | Tag |
| ----- | ----------------------------------------------------- | --- |
| 09    | Agent teams: JSONL mailbox + actor coordination       | —   |
| 10    | Team protocols: request-response with correlation IDs | —   |
| 11    | Autonomous agents: idle-poll-claim cycle              | —   |
| 12    | Worktree isolation: `git worktree` via Process        | —   |

## Architecture

Two-target Swift Package Manager project:

```
swift-claude-code/
├── Package.swift
├── Sources/
│   ├── Core/                ← library (all logic)
│   │   ├── API/
│   │   ├── Agent.swift      agent loop + tool dispatch
│   │   └── ShellExecutor.swift
│   └── cli/                 ← executable (@main entry point)
└── Tests/CoreTests/
```

**Core** is the library — API client, shell executor, agent loop, tools, everything testable. **cli** is just the entry point. The executable is called `claude`.

Raw HTTP to `POST https://api.anthropic.com/v1/messages` using [AsyncHTTPClient](https://github.com/swift-server/async-http-client). Works on both macOS and Linux.

## Non-Goals

This project is **not**:

- A full Claude Code clone or drop-in replacement
- A general-purpose multi-agent framework
- Production-ready IDE tooling

It's a staged exploration of coding-agent architecture — intentionally minimal, intentionally incomplete.

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
swift run claude
```

## References

- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages) — the single endpoint the entire agent talks to
- [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview) — how tool definitions, `tool_use`, and `tool_result` work

## License

MIT
