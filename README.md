# swift-claude-code

A Claude Code-style coding agent, rebuilt from scratch in Swift one stage at a time to find out what actually makes coding agents work.

![demo](demo.gif)

## Table of Contents

- [Background](#background)
- [Philosophy](#philosophy)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

## Background

Claude Code feels unusually effective next to other coding agents, and most of that seems to come from architectural restraint rather than complexity. This project tests that idea by rebuilding the core mechanics in Swift, one stage at a time, to see how little architecture you actually need.

Each stage isolates a single mechanism and adds it to a kernel that never changes. The whole agent reduces to one loop: send the conversation plus tool definitions to the model, run whatever tools it asks for, feed the results back, repeat until it stops calling tools. Every stage adds entries to the tool handler dictionary and injection points before the API call. The loop body stays fixed.

A 9-part learning series walks through each stage on [ivanmagda.dev](https://ivanmagda.dev/posts/s00-bootstrapping-the-project). Progress is tracked with git tags (`00-bootstrap` through `08-background-tasks`), so you can check out any tag and read the code for that stage in isolation. The `docs/` directory holds the written guide for each stage.

## Philosophy

The project tests a few specific claims about coding agents:

- A small number of high-quality tools beats a large tool catalog.
- The model should do most of the heavy lifting. Keep orchestration thin.
- Explicit task state improves reliability more than prompt-only planning.
- Controlled context injection matters more than persistent memory.
- Context compaction is a product feature, not just a token optimization.

Claude Code doesn't ship many tools, and the ones it has are simple: search, file editing, shell. They're just good, and the system trusts the model to drive them. This rebuild follows the same bet across two phases. Phase 1 builds the minimum viable agent: a loop and a handful of good tools. Phase 2 adds the product mechanics that make an agent usable in practice: subagents, skills, context compaction, persistent tasks, and background execution.

What it deliberately is not: a full Claude Code clone, a general-purpose multi-agent framework, or production IDE tooling. It's a staged exploration, intentionally minimal and intentionally incomplete.

## Features

The agent talks to a single endpoint, `POST https://api.anthropic.com/v1/messages`, and exposes these tools to the model:

- `bash` — run shell commands, foreground or in the background.
- `read_file`, `write_file`, `edit_file` — file operations with path safety, where `edit_file` does exact find-and-replace.
- `todo` — track in-progress work, with nag reminders injected back into the loop.
- `agent` — spawn a subagent that runs the same loop with fresh context.
- `load_skill` — load a `skills/{name}/SKILL.md` file on demand and inject its body as a tool result.
- `compact` — compress conversation history with a 3-layer strategy (micro, auto, manual).
- `task_create`, `task_update`, `task_list`, `task_get` — file-based task CRUD with a dependency DAG.
- `background_run`, `background_check` — hand a slow command to a worker, get a job ID back, and keep the loop moving while it runs.

It runs as an interactive REPL and works on both macOS and Linux.

## Installation

### Prerequisites

- Swift 6.2 or newer (the package sets `swift-tools-version: 6.2`).
- macOS 10.15 or newer, or Linux.
- An Anthropic API key.

### Build

```bash
git clone https://github.com/ivan-magda/swift-claude-code.git
cd swift-claude-code
swift build
```

### Configuration

The agent reads two variables, both required. Set them in your environment or in a `.env` file at the project root:

- `ANTHROPIC_API_KEY` — your key from [console.anthropic.com](https://console.anthropic.com/).
- `MODEL_ID` — the model to run, for example `claude-sonnet-4-6`.

Copy the template and fill it in:

```bash
cp .env.example .env
# edit .env with your ANTHROPIC_API_KEY and MODEL_ID
```

Environment variables take precedence over the `.env` file. If either value is missing, the agent exits at startup.

## Usage

Run the executable from a directory you want the agent to work in. That directory becomes its working directory for file and shell operations:

```bash
swift run agent
```

You get an interactive prompt. Type a request and the agent runs its loop until it has an answer:

```
> create a file hello.txt containing "hi" and read it back
```

Type `exit`, `quit`, or `q` to leave, or press Ctrl+C.

## Project Structure

A two-target Swift Package Manager project. The executable product is named `agent`.

```
Sources/
  cli/                 # entry point and REPL; resolves env, starts the loop
  Core/                # the library: agent loop, API client, tools, managers
    Agent.swift            # the loop, tool definitions, tool dispatch
    API/                   # APIClient, request/response models, JSONValue
    ShellExecutor.swift    # Foundation Process wrapper for bash
    TodoManager.swift      # stage 03
    SkillLoader.swift      # stage 05
    ContextCompactor.swift # stage 06
    TaskManager.swift      # stage 07
    BackgroundManager.swift# stage 08 — the only actor in the codebase
Tests/CoreTests/       # tests for the Core library
docs/                  # s00–s08 written guide, one file per stage
skills/example/        # sample SKILL.md showing the skill file format
```

`Core` carries all the logic and is also exposed as a library product. `cli` is a thin wrapper: it resolves the API key and model, builds an `Agent`, and runs the REPL.

The stages map to git tags:

| Stage | Adds | Tag |
| ----- | ---- | --- |
| 00 | SPM project, two-target layout, CI | `00-bootstrap` |
| 01 | Agent loop + bash tool | `01-agent-loop` |
| 02 | Tool dispatch: `read_file`, `write_file`, `edit_file` with path safety | `02-tool-dispatch` |
| 03 | Todo tracking with nag reminder injection | `03-todo-write` |
| 04 | Subagents: recursive loop with fresh context | `04-subagents` |
| 05 | Skill loading: `.md` files injected as tool results | `05-skill-loading` |
| 06 | Context compaction: micro, auto, manual | `06-context-compaction` |
| 07 | Task system: file-based CRUD with dependency DAG | `07-task-system` |
| 08 | Background tasks: `Task {}` + actor-based notification queue | `08-background-tasks` |

## Contributing

This is a teaching project that follows a fixed stage sequence, so large feature additions are out of scope. Bug fixes, clarity improvements to the guides, and corrections are welcome. Open an issue or a pull request against `master`.

Run the test suite before submitting:

```bash
swift test
```

## License

[MIT](LICENSE) © 2026 Ivan Magda
