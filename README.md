# harness-loop

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Claude Code skill that orchestrates structured, multi-phase development projects with parallel execution, progress notifications, and cross-session resume.

## How It Works

```
┌───────────────────────────────────────────────────────┐
│  Harness Loop (outer — prompt-driven state machine)   │
│                                                       │
│  Read tasks.json → pick ready tasks → dispatch →      │
│  collect results → update state → repeat              │
│                                                       │
│  ┌──────────────────────────────────────────────┐     │
│  │  Agent Loop (inner — Claude Code built-in)   │     │
│  │  think → tool → observe → repeat             │     │
│  └──────────────────────────────────────────────┘     │
│                                                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ Subagent │ │ Subagent │ │ Subagent │  (parallel)   │
│  │ arch-1   │ │ arch-2   │ │ arch-3   │               │
│  └──────────┘ └──────────┘ └──────────┘               │
└───────────────────────────────────────────────────────┘
```

Two nested loops:

- **Harness Loop (outer)** — instructions in SKILL.md that make Claude behave as a state machine: read file-based state, pick tasks, dispatch work, update state, repeat.
- **Agent Loop (inner)** — Claude Code's built-in think → tool → observe → repeat cycle, handling one well-scoped task.
- **Subagents** — Claude Code's `Agent` tool runs independent tasks in parallel. The orchestrator is the sole writer of state files.

## Architecture

```
┌─ Controller (interactive session)
│  • Collects requirements
│  • Generates and confirms task DAG
│  • Spawns background worker
│  • Handles pause / resume / stop / status
│
└─ Worker (background process)
   • Executes task DAG via harness loop
   • Sends Telegram notifications
   • Checks .harness/signals/ between tasks
   • Writes all state to .harness/
```

## Install

```bash
git clone https://github.com/spacelobster88/harness-loop.git
cd harness-loop
./install.sh --global    # symlinks to ~/.claude/skills/harness-loop/
```

Then in any Claude Code session:

```
/harness-loop
```

Uninstall: `./uninstall.sh --global`

## Quick Start

1. `/harness-loop` in any Claude Code session
2. Describe your project when prompted
3. Review the task DAG — approve or modify
4. Choose execution mode:
   - **Interactive** — tasks run in your current session
   - **Background** — worker process with Telegram notifications

## Commands

| Command | Action |
|---------|--------|
| `/harness-loop` | Start new project or resume existing |
| `/harness-loop status` | Progress summary |
| `/harness-loop tasks` | Full DAG with statuses |
| `/harness-loop pause` | Pause after current task |
| `/harness-loop resume` | Resume paused worker |
| `/harness-loop stop` | Graceful shutdown |
| `/harness-loop reset` | Reset blocked/in-progress tasks |
| `/harness-loop add <desc>` | Add a task interactively |

## Task DAG

Projects are decomposed into a directed acyclic graph across four phases:

| Phase | Prefix | Focus |
|-------|--------|-------|
| Architecture | `arch-*` | API design, data models, system structure |
| UI/UX | `uiux-*` | Wireframes, component specs, user flows |
| Engineering | `eng-*` | Implementation code |
| QA | `qa-*` | Tests, validation, bug fixes |

Tasks within a phase run in parallel via subagents. Cross-phase dependencies are enforced automatically. The orchestrator uses a **single-writer pattern** — only the main loop reads/writes `tasks.json`; subagents never touch state files.

Before dispatching parallel batches, output file overlap is checked. Tasks sharing output files are serialized automatically.

### QA Feedback Loop

When a QA task finds non-trivial bugs, the orchestrator automatically creates `eng-fix-*` tasks and appends them to the DAG. This forms a closed feedback loop: QA discovers bugs → orchestrator generates fix tasks → engineers fix → QA re-validates.

```
qa-1 completes, reports bugs
        │
        ▼
┌─────────────────────────────────┐
│  Orchestrator (Step 7b)         │
│                                 │
│  1. Parse bug reports from QA   │
│  2. Check convergence limits    │
│  3. Create eng-fix-* tasks      │
│  4. Add them as deps of qa-1    │
│  5. Reset qa-1 → pending        │
│  6. Increment qa_cycle_count    │
└─────────────────────────────────┘
        │
        ▼
eng-fix-1, eng-fix-2 execute
        │
        ▼
qa-1 re-runs (validates fixes)
        │
        ▼
  pass? → done
  fail? → loop (up to MAX_QA_CYCLES)
```

**QA agents** report bugs as structured JSON:

```json
{
  "bugs": [
    {
      "description": "Login fails with special chars in password",
      "affected_files": ["src/auth.ts"],
      "suggested_fix": "Escape special chars in validation regex",
      "severity": "critical"
    }
  ]
}
```

Trivial bugs (< 5 lines) are fixed in place by the QA agent. Non-trivial bugs produce `eng-fix-*` tasks that inherit the QA task's engineering dependencies, so they can run immediately.

**Convergence guarantees** — three layers prevent infinite loops:

| Layer | Limit | Behavior |
|-------|-------|----------|
| Per-task | `MAX_QA_CYCLES = 3` | Each QA task can trigger at most 3 fix-and-retest cycles |
| Global | `MAX_REWORK_TASKS = 8` | Max 8 `eng-fix-*` tasks across the entire project |
| Outer | `MAX_ITERATIONS = 50` | Hard stop on the execute loop |

When limits are reached, remaining bugs are recorded as known issues in the final report.

### Dead Loop Prevention

| Safeguard | Trigger | Action |
|-----------|---------|--------|
| Max retries | 3 failures | Task marked `blocked` |
| Stale detection | 2 rounds with no progress | Loop breaks, user notified |
| Iteration cap | 50 iterations | Hard stop |
| Signal check | `.harness/signals/stop` | Graceful shutdown |

## Centurion Integration

Requires [Centurion](https://github.com/spacelobster88/centurion) for resource-aware subagent scheduling. Before every batch, the harness loop queries Centurion to size the next batch.

- **`recommended_max_agents`** — concurrent subagent capacity from CPU, RAM, and load. Batch size = `max(1, recommended_max_agents - active_agents)`.
- **`memory_pressure`** — safety override:
  - `normal`: no action
  - `warn`: batch size capped at 2
  - `critical`: batch size = 1, pause 60s and re-query; if still critical, stop and notify

| Mode | Source |
|------|--------|
| **Headless** (Telegram Bot) | `[Centurion Status]` block injected by bot backend |
| **Interactive** (local) | `curl http://localhost:${CENTURION_PORT:-8100}/api/centurion/hardware` |

## Telegram Bot Mode

When running via a Telegram bot (`[TELEGRAM_BOT_MODE]` in context), harness-loop operates in split-phase mode:

1. **Foreground (planning)** — requirements gathering and plan confirmation happen interactively in chat.
2. **Handoff** — on DAG approval, outputs `[HARNESS_EXEC_READY]`. The bot detects this and starts a background session.
3. **Background (execution)** — runs one batch per invocation, exits with a chaining marker (`[HARNESS_BATCH_DONE]`, `[HARNESS_COMPLETE]`, or `[HARNESS_BLOCKED]`). The bot chains invocations until completion. Foreground chat stays free.

Resume: if `.harness/` exists with in-progress tasks, outputs a status summary + `[HARNESS_EXEC_READY]` for user confirmation before resuming.

### Background Mode Setup

```bash
export HARNESS_TG_TOKEN="your-bot-token"
export HARNESS_TG_CHAT_ID="your-chat-id"
```

## Project Structure

```
harness-loop/
├── SKILL.md                    # Core skill (controller mode)
├── worker/
│   └── WORKER_PROMPT.md        # Background worker prompt
├── references/
│   ├── workflow.md             # Phase lifecycle docs
│   ├── task-schema.md          # DAG schema reference
│   ├── role-prompts.md         # Agent role focus prompts
│   └── worker-protocol.md     # Worker execution protocol
├── scripts/
│   ├── init-harness.sh         # Scaffold .harness/ directory
│   ├── worker.sh               # Launch background worker
│   ├── notify.sh               # Telegram notification wrapper
│   ├── validate-tasks.py       # DAG validation + tests
│   └── status.sh               # Quick status summary
├── assets/
│   └── task-schema.json        # Formal JSON Schema
├── examples/
│   ├── tasks-example.json      # Example task DAG
│   └── progress-example.md     # Example progress log
├── install.sh
└── uninstall.sh
```

### State Files (per-project)

```
.harness/
├── config.json         # Project metadata
├── requirements.md     # Captured requirements
├── tasks.json          # Task DAG (source of truth)
├── progress.md         # Human-readable log
├── worker.log          # Worker output log
├── worker.pid          # Worker process ID
└── signals/
    ├── pause           # Pause signal
    └── stop            # Stop signal
```

## Validation

```bash
python scripts/validate-tasks.py .harness/tasks.json   # validate a DAG
python scripts/validate-tasks.py --test                 # run built-in tests
```

Validates: JSON schema, dependency existence, cycle detection, output file overlap, ID format, acceptance criteria.

## References

- [Centurion](https://github.com/spacelobster88/centurion) — Resource monitor for agent scheduling (required)
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic engineering blog
- [ralph](https://github.com/snarktank/ralph) — Inspiration for multi-phase agent orchestration

## License

MIT
