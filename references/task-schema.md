# Task DAG Schema Reference

## File Location
`.harness/tasks.json`

## Structure

```json
{
  "metadata": {
    "project_name": "string",
    "created_at": "ISO 8601 datetime",
    "updated_at": "ISO 8601 datetime",
    "current_phase": "requirements | architecture | uiux | engineering | qa | complete",
    "telegram_chat_id": "string (optional)",
    "telegram_bot_token_env": "string (optional, env var name)",
    "rework_tasks_created": "int (default 0, tracks eng-fix tasks created by QA feedback)"
  },
  "tasks": [ ...task objects... ]
}
```

## Task Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Format: `{phase}-{number}`. Examples: `arch-1`, `uiux-2`, `eng-3`, `qa-4`, `eng-fix-1` |
| `title` | string | yes | Short title, max 80 chars |
| `description` | string | yes | Detailed description of what the task involves |
| `phase` | enum | yes | `architecture`, `uiux`, `engineering`, `qa` |
| `status` | enum | yes | `pending`, `in_progress`, `done`, `blocked` |
| `dependencies` | string[] | yes | List of task IDs that must be `done` before this starts |
| `acceptance_criteria` | string[] | yes | Verifiable conditions for completion |
| `output_files` | string[] | no | Files this task creates or modifies |
| `retry_count` | int | no | Number of failed attempts (default 0, max 3) |
| `started_at` | string\|null | no | ISO 8601 datetime when execution began |
| `completed_at` | string\|null | no | ISO 8601 datetime when marked done |
| `notes` | string\|null | no | Free-form notes about execution |
| `qa_cycle_count` | int | no | QA feedback cycles triggered (default 0, max 3). Only for qa-phase tasks. |

## ID Conventions

| Prefix | Phase | Examples |
|--------|-------|---------|
| `arch-` | Architecture | `arch-1`, `arch-2` |
| `uiux-` | UI/UX | `uiux-1`, `uiux-2` |
| `eng-` | Engineering | `eng-1`, `eng-2` |
| `eng-fix-` | Engineering (bug fix from QA) | `eng-fix-1` |
| `qa-` | QA | `qa-1`, `qa-2` |

## Dependency Rules

1. `arch-*` tasks: may depend on other `arch-*` tasks, or have no dependencies
2. `uiux-*` tasks: may depend on `arch-*` tasks or have no dependencies
3. `eng-*` tasks: MUST depend on at least one `arch-*` task; SHOULD depend on relevant `uiux-*` tasks
4. `qa-*` tasks: MUST depend on the `eng-*` task(s) they test
5. `eng-fix-*` tasks: depend on the `qa-*` task that found the bug (or on relevant `eng-*` tasks)
6. **No circular dependencies**: The graph must be a DAG (directed acyclic graph)
7. **All referenced dependencies must exist**: If task A depends on `arch-1`, then `arch-1` must exist in the tasks array

## File Overlap Rule

If two tasks have overlapping `output_files` (same file appears in both), they MUST have a dependency between them (one depends on the other). This prevents parallel write conflicts.

## Acceptance Criteria Guidelines

Good criteria are:
- **Specific**: "API returns 200 for valid input" not "API works"
- **Verifiable**: Can be checked by reading a file, running a command, or running a test
- **Binary**: Pass or fail, no ambiguity

Examples:
- "File `src/auth.ts` exports `login()`, `register()`, `logout()` functions"
- "Running `npm test` passes with 0 failures"
- "Database schema in `docs/schema.md` includes users, sessions, and posts tables"
- "Error responses use `{error: string, code: number}` format consistently"

## Task Granularity

Each task should:
- Complete in 1-3 agent loop iterations (roughly 5-15 tool calls)
- Produce 1-3 files
- Have 2-5 acceptance criteria

If a task seems too large, split it. Signs it's too large:
- More than 5 output files
- More than 5 acceptance criteria
- Description is longer than 3 sentences
- Involves multiple unrelated concerns
