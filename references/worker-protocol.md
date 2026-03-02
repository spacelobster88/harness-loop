# Worker Protocol Reference

## Overview

The worker is a background Claude CLI process (`claude -p`) that executes the task DAG autonomously. It runs independently of any interactive session, freeing the user to continue using Claude Code for other tasks.

## Launching the Worker

The worker is launched via `scripts/worker.sh`, which:
1. Reads `HARNESS_TG_TOKEN` and `HARNESS_TG_CHAT_ID` from environment (or `.harness/config.json`)
2. Sends an initial notification: "▶️ Harness worker started ({pending_count} tasks pending)"
3. Invokes `claude -p --dangerously-skip-permissions` with the worker prompt
4. Runs via `nohup` so it survives terminal disconnection
5. Logs output to `.harness/worker.log`

## Signal Files

The worker checks for signal files in `.harness/signals/` between each task:

| File | Effect |
|------|--------|
| `.harness/signals/pause` | Worker finishes current task, then exits. Notify: "⏸️ Paused" |
| `.harness/signals/stop` | Worker finishes current task, then exits. Notify: "🛑 Stopped" |

Signal files are plain empty files. Create them with `touch`, remove with `rm`.

The controller (interactive session) manages signals:
- `/harness-loop pause` → creates pause signal
- `/harness-loop resume` → removes pause signal, re-spawns worker
- `/harness-loop stop` → creates stop signal

## Telegram Notifications

The worker sends notifications via `scripts/notify.sh` at these events:

| Event | Message |
|-------|---------|
| Worker started | `▶️ Harness worker started (N tasks pending)` |
| Task completed | `✅ {task_id}: {title} ({done}/{total})` |
| Task failed | `⚠️ {task_id} failed (attempt {n}/3)` |
| Task blocked | `🚫 {task_id} blocked after 3 attempts` |
| Batch started | `🔄 Starting batch: {task_ids}` |
| Stalled | `🛑 No progress in 2 rounds. Worker paused.` |
| Paused | `⏸️ Worker paused by signal` |
| Stopped | `🛑 Worker stopped by signal` |
| Complete | `🎉 All {total} tasks complete!` |

## Worker State Management

The worker is the SOLE writer of:
- `.harness/tasks.json` — task statuses, timestamps, notes
- `.harness/progress.md` — human-readable log

Write protocol:
1. BEFORE starting a task: set `status: "in_progress"`, `started_at`, write tasks.json
2. AFTER completing a task: set `status: "done"`, `completed_at`, write tasks.json
3. This ensures crash recovery: at most one task needs re-evaluation on resume

## Crash Recovery

If the worker crashes or is killed:
1. At most one task will have `status: "in_progress"`
2. On next launch, the worker (or controller) checks this task:
   - Inspects `output_files`: do they exist and look complete?
   - Inspects `acceptance_criteria`: can they be verified?
   - If criteria met → mark `done`
   - If not → reset to `pending`
3. Continue from there

## Resource Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| Max retries per task | 3 | Prevent infinite retry |
| Max stale rounds | 2 | Detect stuck loops |
| Max total iterations | 50 | Hard cap on loop cycles |
| Task timeout | 300s (5 min) | Per-task execution limit |

## Worker Log

The worker logs to `.harness/worker.log`. Format:
```
[2026-03-02T10:00:00Z] STARTED worker
[2026-03-02T10:00:05Z] TASK arch-1 IN_PROGRESS
[2026-03-02T10:02:30Z] TASK arch-1 DONE (2m25s)
[2026-03-02T10:02:31Z] NOTIFY ✅ arch-1: Design API schema (1/12)
[2026-03-02T10:02:32Z] SIGNAL pause detected
[2026-03-02T10:02:32Z] PAUSED
```
