# harness-loop

A Claude Code skill that orchestrates structured, multi-phase development projects with parallel execution, progress notifications, and cross-session resume.

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  Harness Loop (outer — prompt-driven state machine)  │
│                                                       │
│  Read tasks.json → pick ready tasks → dispatch →      │
│  collect results → update state → repeat              │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  Agent Loop (inner — Claude Code built-in)    │    │
│  │  think → tool → observe → repeat              │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │ Subagent │ │ Subagent │ │ Subagent │  (parallel)  │
│  │ arch-1   │ │ arch-2   │ │ arch-3   │             │
│  └──────────┘ └──────────┘ └──────────┘             │
└─────────────────────────────────────────────────────┘
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

- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic engineering blog
- [ralph](https://github.com/snarktank/ralph) — Inspiration for multi-phase agent orchestration

## License

MIT
