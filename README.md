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
│  │  Agent Loop (inner — Claude Code built-in)    │    │
│  │  think → tool → observe → repeat              │    │
│  └──────────────────────────────────────────────┘     │
│                                                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ Subagent │ │ Subagent │ │ Subagent │  (parallel)   │
│  │ arch-1   │ │ arch-2   │ │ arch-3   │               │
│  └──────────┘ └──────────┘ └──────────┘               │
└───────────────────────────────────────────────────────┘
```

- **Agent Loop (inner)**: Claude Code's built-in think → tool → observe → repeat cycle. Handles one well-scoped task.
- **Harness Loop (outer)**: Instructions in SKILL.md that make Claude behave as a state machine — read file-based state, pick tasks, dispatch work, update state, repeat.
- **Subagents**: Claude Code's `Agent` tool runs independent tasks in parallel. The orchestrator is the sole writer of state files.

## Architecture: Controller + Worker

```
┌─ Controller (lightweight, runs in interactive session)
│  • Collects requirements interactively
│  • Generates and confirms task DAG with user
│  • Spawns background worker
│  • Handles pause/resume/stop/status commands
│
└─ Worker (background process, runs independently)
   • Executes task DAG via harness loop algorithm
   • Sends Telegram progress notifications
   • Checks .harness/signals/ between tasks for pause/stop
   • Writes all state to .harness/ files
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

### Uninstall

```bash
./uninstall.sh --global
```

## Quick Start

1. **Start a new project**: `/harness-loop` in any Claude Code session
2. **Describe your project** when prompted
3. **Review the task DAG** — approve, or modify tasks
4. **Choose execution mode**:
   - **Interactive**: Tasks run in your current session
   - **Background**: Worker process with Telegram notifications

### Background Mode Requirements

Set environment variables for Telegram notifications:

```bash
export HARNESS_TG_TOKEN="your-bot-token"
export HARNESS_TG_CHAT_ID="your-chat-id"
```

## Commands

| Command | Action |
|---------|--------|
| `/harness-loop` | Start new project or resume existing |
| `/harness-loop status` | Progress summary |
| `/harness-loop tasks` | Show full DAG with statuses |
| `/harness-loop pause` | Pause worker after current task |
| `/harness-loop resume` | Resume paused worker |
| `/harness-loop stop` | Stop worker gracefully |
| `/harness-loop reset` | Reset blocked/in-progress tasks |
| `/harness-loop add <desc>` | Add a task interactively |

## Centurion Integration

harness-loop requires [Centurion](https://github.com/spacelobster88/centurion) for resource-aware subagent scheduling. Before every batch iteration, the harness loop queries Centurion to determine how many subagents can safely run in parallel.

### How It Works

1. **Pre-flight check**: Before entering the execute loop, harness-loop verifies that Centurion resource data is available. If Centurion is unreachable, the loop will not start.
2. **Per-iteration memory checkpoint**: At the top of every loop iteration, harness-loop obtains the current resource state from Centurion and uses it to size the next batch.

### Data Flow

Centurion provides two key values:

- **`recommended_max_agents`** — the number of concurrent Claude Code subagents the machine can handle, computed from CPU, RAM, and load. The batch size is calculated as `max(1, recommended_max_agents - active_agents)`.
- **`memory_pressure`** — a safety override with three levels:
  - `normal`: no action
  - `warn`: batch size capped at 2
  - `critical`: batch size set to 1, loop pauses for 60 seconds and re-queries. If still critical, the loop stops and notifies the user.

### Dual-Mode Resolution

Centurion data can arrive via two paths depending on the execution context:

| Mode | Source | Mechanism |
|------|--------|-----------|
| **Headless** (Telegram Bot Mode) | `[Centurion Status]` block injected into context by the bot backend | No curl needed — data is pre-fetched |
| **Interactive** (local Claude Code) | `curl http://localhost:${CENTURION_PORT:-8100}/api/centurion/hardware` | Direct query at each iteration |

Configure the port via the `CENTURION_PORT` environment variable (default: `8100`).

## Telegram Bot Mode

When harness-loop runs via a Telegram bot (indicated by `[TELEGRAM_BOT_MODE]` in the injected context), it operates in a split-phase mode that keeps the foreground chat free for other interactions.

### Split-Phase Execution

**Phase 1 — Foreground (planning):**
- Requirements gathering, design brainstorming, and plan confirmation happen interactively in the Telegram chat.
- Each user reply arrives as a new `claude -p --continue` call.

**Phase 2 — Handoff:**
- When the user approves the task DAG, harness-loop outputs the marker `[HARNESS_EXEC_READY]` at the end of its response.
- The Telegram bot detects this marker and automatically starts a background session for execution.

**Phase 3 — Background (execution):**
- A new `claude -p --continue` session runs in the background.
- The execute loop runs one batch per invocation, then exits with a chaining marker (`[HARNESS_BATCH_DONE]`, `[HARNESS_COMPLETE]`, or `[HARNESS_BLOCKED]`).
- The bot chains subsequent invocations automatically until all tasks are complete or the loop is blocked.
- The foreground Telegram chat remains free for other conversations.

### Resume in Telegram Bot Mode

If a previous harness project exists (`.harness/` directory with in-progress tasks), harness-loop detects it and outputs a status summary followed by `[HARNESS_EXEC_READY]`, allowing the bot to gate for user confirmation before resuming background execution.

## Usage Examples

### Start a New Project (Interactive)

```
> /harness-loop
# Claude asks for project requirements
> Build a REST API for a todo app with auth, CRUD, and tests
# Claude generates a task DAG and asks for approval
> looks good, go ahead
# Choose interactive or background mode
> interactive
# Harness loop begins executing tasks
```

### Start a New Project (via Telegram)

```
You: /harness build a CLI tool for log analysis
Bot: What types of logs? What output format? ...
You: Apache logs, JSON output, support filtering by date
Bot: Here's the task DAG: 3 arch, 2 eng, 2 qa tasks. Approve?
You: yes
Bot: Plan confirmed. Starting background execution...
     [background worker runs automatically]
Bot: Batch 1 complete: arch-1, arch-2 done (2/7)
Bot: All 7 tasks complete!
```

### Check Status

```
> /harness-loop status
# Shows: phases completed, tasks done/total, blocked tasks, current batch
```

### Pause and Resume

```
> /harness-loop pause
# Worker finishes current task, then pauses
> /harness-loop resume
# Worker continues from where it left off
```

## Task DAG

Projects are decomposed into a task DAG with four phases:

| Phase | Prefix | Focus |
|-------|--------|-------|
| Architecture | `arch-*` | API design, data models, system structure |
| UI/UX | `uiux-*` | Wireframes, component specs, user flows |
| Engineering | `eng-*` | Implementation code |
| QA | `qa-*` | Tests, validation, bug fixes |

Tasks within a phase can run in parallel via subagents. Cross-phase dependencies are enforced automatically.

### Parallel Execution

The orchestrator uses a **single-writer pattern**: only the main loop reads/writes `tasks.json`. Subagents execute tasks and return results — they never touch state files.

Before dispatching parallel batches, output file overlap is checked. Tasks sharing output files are serialized automatically.

### Dead Loop Prevention

| Safeguard | Trigger | Action |
|-----------|---------|--------|
| Max retries | 3 failures | Task marked `blocked` |
| Stale detection | 2 rounds with no progress | Loop breaks, user notified |
| Iteration cap | 50 iterations | Hard stop |
| Signal check | `.harness/signals/stop` | Graceful shutdown |

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
├── install.sh                  # Symlink installer
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
# Validate a task DAG
python scripts/validate-tasks.py .harness/tasks.json

# Run built-in tests
python scripts/validate-tasks.py --test
```

Validates: JSON schema, dependency existence, cycle detection, output file overlap, ID format, acceptance criteria.

## References

- [Centurion](https://github.com/spacelobster88/centurion) — Resource monitor for agent scheduling (required)
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic engineering blog
- [ralph](https://github.com/snarktank/ralph) — Inspiration for multi-phase agent orchestration

## License

MIT
