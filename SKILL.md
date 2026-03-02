---
name: harness-loop
description: |
  Orchestrate structured multi-phase development projects with parallel execution,
  progress notifications, and cross-session resume. Use when the user wants to plan
  and build a project from scratch, resume an in-progress project (has .harness/
  directory), or says "harness loop", "plan and build", or "start a project".
  Decomposes work into a task DAG and guides Claude through requirements, architecture,
  UI/UX, engineering, and QA phases — executing independent tasks in parallel via
  subagents while maintaining a single source of truth in .harness/tasks.json.
version: 1.0.0
license: MIT
---

# Harness Loop

An outer orchestration loop that rides on Claude Code's built-in agent loop. It decomposes projects into a task DAG, tracks state in files, and directs the agent loop to execute tasks — in parallel where possible.

## How It Works

**Agent Loop (inner)**: Claude Code's built-in think → tool → observe → repeat cycle.
**Harness Loop (outer)**: This skill's instructions that make Claude behave as a state machine — read state, pick tasks, dispatch, update, repeat.
**Subagents**: Claude Code's Agent tool runs independent tasks in parallel. The main loop (orchestrator) is the sole writer of state files.

## Determine Mode

Check if `.harness/` directory exists:
- **No .harness/**: This is a new project → go to [New Project](#new-project)
- **Has .harness/**: This is a resume → go to [Resume](#resume)

Check if the user passed arguments:
- `/harness-loop status` → Read `.harness/tasks.json`, show summary of tasks by status and phase. Do NOT enter the loop.
- `/harness-loop tasks` → Read `.harness/tasks.json`, display the full DAG with statuses and dependency arrows. Do NOT enter the loop.
- `/harness-loop pause` → Write an empty file at `.harness/signals/pause`. Confirm to user.
- `/harness-loop resume` → Remove `.harness/signals/pause` if it exists. Then go to [Resume](#resume).
- `/harness-loop stop` → Write an empty file at `.harness/signals/stop`. Confirm to user.
- `/harness-loop reset` → Reset all tasks with status `in_progress` or `blocked` to `pending`, set their `retry_count` to 0. Write tasks.json.
- `/harness-loop add <description>` → Ask user for details, determine phase and dependencies, add task to DAG.

## New Project

### Step 1: Initialize

Run the init script:
```bash
bash <skill-dir>/scripts/init-harness.sh
```

### Step 2: Requirements Gathering

Ask the user: **"What would you like to build? Describe the project in as much detail as you can."**

Then ask 3-5 clarifying questions based on their answer. Focus on:
- Scope: What's in v1 vs future?
- Users: Who uses this? What's the primary use case?
- Tech stack: Any preferences or constraints?
- Constraints: Performance, security, compatibility requirements?
- Must-have vs nice-to-have features

Capture all answers in `.harness/requirements.md`. Present a structured summary and ask for approval.

### Step 3: Task Decomposition

Generate a task DAG in `.harness/tasks.json` following these rules:

1. **Phase order**: architecture → uiux → engineering → qa
2. **Dependencies**: `eng-*` depends on relevant `arch-*` and `uiux-*`. `qa-*` depends on `eng-*`.
3. **Task granularity**: Each task should complete in 1-3 agent loop iterations. If bigger, split it.
4. **File isolation**: Assign `output_files` to each task. If two tasks share output files, add a dependency between them.
5. **Acceptance criteria**: Every task must have specific, verifiable criteria.

Run validation after generating:
```bash
python <skill-dir>/scripts/validate-tasks.py .harness/tasks.json
```

Present the DAG to the user with a visual summary showing phases, task counts, and dependency structure. Ask for approval. User may add, remove, or modify tasks.

### Step 4: Choose Execution Mode

Ask the user:
- **Interactive mode**: Execute tasks in this session. You (the user) can observe and intervene. Best for small projects or when you want close control.
- **Background mode**: Spawn a worker process. You'll get Telegram notifications for progress. Best for large projects. Requires `HARNESS_TG_TOKEN` and `HARNESS_TG_CHAT_ID` environment variables.

For **interactive mode** → go to [Execute Loop](#execute-loop).
For **background mode** → run:
```bash
bash <skill-dir>/scripts/worker.sh
```
Then confirm to user: "Worker started. You'll receive Telegram notifications. Use `/harness-loop status` to check progress, `/harness-loop pause` to pause."

## Resume

1. Read `.harness/tasks.json` and `.harness/progress.md`
2. Check for tasks with `status: "in_progress"`:
   - Inspect their `acceptance_criteria` and `output_files`
   - If criteria appear met → mark `done`
   - If not → reset to `pending`
3. Report current state to user: phases completed, tasks remaining, any blocked tasks
4. Ask user: continue in interactive or background mode?

## Execute Loop

This is the core harness loop. Follow this algorithm precisely:

```
CONSTANTS:
  MAX_RETRIES = 3
  MAX_STALE_ROUNDS = 2
  MAX_ITERATIONS = 50

STATE:
  stale_count = 0
  iteration = 0

LOOP:
  1. Read .harness/tasks.json
  2. Count done tasks vs total → if all done, go to COMPLETE
  3. Find ready tasks: status == "pending" AND all dependencies have status == "done"
  4. If no ready tasks:
     - If any tasks are "blocked": report to user, ask for guidance, BREAK
     - If any tasks are "in_progress": something is wrong, reset to pending
     - Otherwise: BREAK with error
  5. Group ready tasks into parallel batches:
     - Collect all output_files from ready tasks
     - Tasks whose output_files overlap with another ready task → cannot be in same batch
     - First batch = maximal set of non-overlapping tasks
  6. If batch has 1 task:
     - Set status → "in_progress", write tasks.json
     - Read references/role-prompts.md for the task's phase
     - Execute the task directly (use agent loop tools: Read, Write, Edit, Bash, etc.)
     - Verify acceptance criteria
     - If success: status → "done", record completed_at
     - If failure: retry_count += 1, if >= MAX_RETRIES → "blocked", else → "pending"
  7. If batch has 2+ tasks:
     - Set all to "in_progress", write tasks.json
     - Read references/role-prompts.md for the tasks' phase
     - Dispatch via Agent tool — one subagent per task, ALL in a single message (parallel)
     - Each subagent receives: task description, acceptance criteria, output files, role prompt
     - Each subagent returns: {status, output_files, notes}
     - Subagents do NOT read or write tasks.json
     - Collect all results
     - Update tasks.json based on results (orchestrator is sole writer)
  8. Log completed tasks to .harness/progress.md
  9. Check signals:
     - If .harness/signals/stop exists → BREAK
     - If .harness/signals/pause exists → BREAK
  10. Check progress:
      - If no tasks moved to "done" this round → stale_count += 1
      - If stale_count >= MAX_STALE_ROUNDS → report to user, BREAK
      - Else → stale_count = 0
  11. iteration += 1
      If iteration >= MAX_ITERATIONS → report to user, BREAK
  12. Go to step 1

COMPLETE:
  - Set metadata.current_phase → "complete"
  - Write final summary to progress.md
  - Report to user: tasks completed, files created, total time
```

## Subagent Contract

When dispatching to a subagent, provide this prompt structure:

```
You are executing a task as part of a structured development project.

## Your Role
{role_prompt from references/role-prompts.md for this task's phase}

## Task
ID: {task.id}
Title: {task.title}
Description: {task.description}

## Acceptance Criteria
{task.acceptance_criteria, one per line}

## Output Files
You should create/modify these files: {task.output_files}
Do NOT modify any other files outside this list.

## Instructions
- Execute the task completely
- Verify all acceptance criteria are met
- Return a brief summary of what you did
```

## Additional References

- Detailed workflow documentation: read `references/workflow.md`
- Task JSON schema and rules: read `references/task-schema.md`
- Role-specific focus prompts: read `references/role-prompts.md`
- Worker protocol and signals: read `references/worker-protocol.md`
- Validate DAG: run `python <skill-dir>/scripts/validate-tasks.py .harness/tasks.json`
- Check status: run `bash <skill-dir>/scripts/status.sh`
