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
**Subagents**: Claude Code's Agent tool runs independent tasks **in background** so the user can still chat. The main loop (orchestrator) is the sole writer of state files.

## CRITICAL: User Responsiveness

**The user MUST be able to chat with you at all times during execution.** Never block the conversation waiting for subagents. All subagent dispatches MUST use `run_in_background: true`. Between dispatching and collecting results, respond to any user messages normally.

## Chat ID Detection

The harness loop sends Telegram notifications to the user who started it. At initialization or resume, detect and store the chat_id:

1. Call `mcp__mini-claude-bot__list_gateway_sessions` to find active gateway sessions
2. Pick the session that is currently busy (that's the user's active chat)
3. Store the chat_id in `.harness/config.json` as `telegram_chat_id`
4. Also store it in `.harness/tasks.json` metadata as `telegram_chat_id`
5. The `notify.sh` script reads from `HARNESS_TG_CHAT_ID` env var OR from `.harness/tasks.json` metadata

If no gateway session is found (running locally), ask the user for their Telegram chat ID.

## Telegram Bot Mode Detection

When running via a Telegram bot (indicated by `[TELEGRAM_BOT_MODE]` in the injected context), the harness loop operates in a split-phase mode:

**Phase 1 (Foreground):** Requirements gathering, design brainstorming, and plan confirmation.
- Follow Steps 1-3 as normal (ask questions, gather requirements, design, decompose tasks)
- Each user reply arrives as a new `claude -p --continue` call
- Respond normally to each message

**Phase 2 Handoff:** When the user confirms the plan (approves the task DAG from Step 3):
- Output the final plan summary with task count and phase breakdown
- Output the marker `[HARNESS_EXEC_READY]` at the very END of your response
- **STOP. Do NOT enter the Execute Loop.** The Telegram bot will detect this marker and automatically start a background session for execution.

**Phase 2 (Background):** The bot starts a new `claude -p --continue` session in background.
- You will receive a message like "Resume the harness-loop. The plan has been confirmed. Enter the Execute Loop now."
- At this point, enter the Execute Loop (Step 4 is skipped — always background mode).
- The foreground chat channel remains free for the user to send other messages.

If `[TELEGRAM_BOT_MODE]` is NOT present in the context, follow the normal interactive flow (Steps 1-4 as written).

## Telegram Bot Mode Execute Loop

When running in Telegram Bot Mode (background phase), the Execute Loop operates differently to keep the foreground chat free and enable real-time `/status` tracking:

**One batch per invocation, then EXIT.** Each background `claude -p --continue` call executes ONE batch of tasks, then exits with a structured marker. The Python backend parses the marker and auto-chains the next invocation. This keeps each invocation short and the foreground responsive.

### Rules

1. **Execute ONE batch per iteration** — find ready tasks, dispatch, collect results, update `tasks.json`, then EXIT with a marker (see below). Do NOT loop back to step 1.
2. **Subagents run INLINE** — since you're already in a background process, do NOT use `run_in_background: true`. Dispatch subagents normally (foreground). The skill's `run_in_background` does not work in `-p` pipe mode.
3. **No user interaction expected** — you are in a background process. Do not ask the user questions. If a task is blocked, exit with `[HARNESS_BLOCKED]`.
4. **All other rules still apply** — Centurion check, memory guardrails, retry/review within the batch, TDD protocol, code review for eng/qa tasks.
5. **Progressive ramp-up persists across invocations** — store `previous_batch_size` in `.harness/config.json` so each chained invocation can read the ramp-up state from the previous batch. Read it at the start, write it before exiting.

### Exit Markers

**CRITICAL: You MUST output exactly one of these markers as the VERY LAST LINE of your response. If you omit the marker, the batch chain STOPS SILENTLY and the entire harness loop stalls. No marker = no next batch. This is the #1 cause of harness loop stalls.**

- `[HARNESS_BATCH_DONE:phase_name:done_count/total_count]` — batch completed, more tasks remain. Example: `[HARNESS_BATCH_DONE:engineering:5/12]`
- `[HARNESS_BLOCKED:task_id:reason]` — a task needs user input. Example: `[HARNESS_BLOCKED:eng-3:API key not configured]`
- `[HARNESS_COMPLETE]` — all tasks done (output after generating the final report)

**The marker MUST be the last line, on its own line, with no trailing text or whitespace after it.** Example of correct output:

```
Updated tasks.json: eng-3 done, eng-4 done. Phase engineering: 5/12 complete.

[HARNESS_BATCH_DONE:engineering:5/12]
```

Do NOT wrap the marker in markdown code blocks, explanatory text, or summaries after it. The backend uses regex to find the marker — anything after it may prevent detection.

The backend will:
- On `BATCH_DONE`: send a short progress message to Telegram, then auto-chain the next batch invocation
- On `BLOCKED`: send a notification to Telegram, stop chaining
- On `COMPLETE`: send a notification, stop chaining
- On no marker: send a warning that the loop may have stalled (no chaining occurs)

## Telegram Progress Notifications

Send notifications at **phase boundaries** (not per-task). Use:
```bash
bash <skill-dir>/scripts/notify.sh "<message>"
```

When to notify:
- **Phase complete**: When ALL tasks in a phase are done. Include a summary of what was accomplished:
  `"Phase '{phase}' complete ({n} tasks done)\n\n{bullet list of task titles and one-line results}\n\nProgress: {done}/{total} total"`
- **Blocked/error**: When a task is blocked after max retries:
  `"Task {id} blocked after {retries} retries. Needs your input."`
- **All done**: When all tasks are complete:
  `"All {total} tasks complete! Sending final report to your email."`

Do NOT send notifications for individual task completions or batch dispatches — that's too noisy. Phase-level summaries only.

Notifications are best-effort — never fail the loop because of a notification error.

## Final Report (Email)

When the harness loop reaches COMPLETE:
1. Generate a comprehensive report covering:
   - Project name and total duration
   - Phase-by-phase summary with task results
   - Key files created/modified
   - Issues encountered and how they were resolved
   - Recommendations for next steps
2. Generate a PDF of the report (use fpdf2 or LaTeX)
3. Send the report via email using the `send-email` skill to the user's email
4. Also write the report to `.harness/reports/final-report.pdf`

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

Then detect the Telegram chat_id (see [Chat ID Detection](#chat-id-detection)) and write it into `.harness/tasks.json` metadata.

### Step 2: Requirements Gathering

Ask the user: **"What would you like to build? Describe the project in as much detail as you can."**

Then ask 3-5 clarifying questions based on their answer. Focus on:
- Scope: What's in v1 vs future?
- Users: Who uses this? What's the primary use case?
- Tech stack: Any preferences or constraints?
- Constraints: Performance, security, compatibility requirements?
- Must-have vs nice-to-have features

Capture all answers in `.harness/requirements.md`. Present a structured summary and ask for approval.

### Step 2.5: Design Brainstorming

**HARD GATE: No task decomposition or implementation until the user approves a design.**

After requirements are approved:

1. **Explore context**: Read the codebase if extending an existing project. Understand conventions, patterns, and constraints.
2. **Propose 2-3 approaches** with trade-offs. For each approach, cover:
   - Architecture overview (components, data flow, APIs)
   - Technology choices and rationale
   - Risks and mitigations
   - Rough complexity estimate
3. **Ask ONE question at a time** if you need clarification. Do not dump a list of questions.
4. **Present the chosen design** as a structured document and write it to `.harness/design.md`.
5. **Get explicit user approval**: "Does this design look good? Any changes before I break it into tasks?"

Do NOT proceed to Step 3 until the user says the design is approved. If the user says "just build it" without reviewing, remind them: "The design phase prevents expensive rework later. It takes 2 minutes to review."

### Step 3: Task Decomposition

Generate a task DAG in `.harness/tasks.json` following these rules:

1. **Phase order**: architecture → uiux → engineering → qa
2. **Dependencies**: `eng-*` depends on relevant `arch-*` and `uiux-*`. `qa-*` depends on `eng-*`.
3. **Task granularity**: Each task should be completable in **2-5 minutes** of agent work (1-3 loop iterations). If bigger, split it.
4. **File isolation**: Assign `output_files` to each task. If two tasks share output files, add a dependency between them.
5. **Acceptance criteria**: Every task must have specific, verifiable criteria.
6. **Plan precision** (engineering and QA tasks MUST include):
   - Exact file paths to create or modify
   - Exact test commands with expected output (e.g., `npm test -- --grep "auth" → 3 passing`)
   - Key function/class names to implement
   - If modifying existing code: the function name and approximate line range

Run validation after generating:
```bash
python <skill-dir>/scripts/validate-tasks.py .harness/tasks.json
```

Present the DAG to the user with a visual summary showing phases, task counts, and dependency structure. Ask for approval. User may add, remove, or modify tasks.

### Step 4: Choose Execution Mode

**If running in Telegram Bot Mode:** Skip this step. Background mode is chosen automatically via the `[HARNESS_EXEC_READY]` handoff mechanism.

Otherwise, ask the user:
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
2. Re-detect the Telegram chat_id (see [Chat ID Detection](#chat-id-detection)) — the user may be resuming from a different chat
3. Check for tasks with `status: "in_progress"`:
   - Inspect their `acceptance_criteria` and `output_files`
   - If criteria appear met → mark `done`
   - If not → reset to `pending`
4. Report current state to user: phases completed, tasks remaining, any blocked tasks
5. **If `[TELEGRAM_BOT_MODE]` is present:** Do NOT ask about mode. Output a status summary (phases, done/total, blocked tasks), then output `[HARNESS_EXEC_READY]` at the END of your response. The bot will gate for user confirmation and start background execution automatically.
6. **If NOT in Telegram Bot Mode:** Ask user: continue in interactive or background mode?

## Historical Project Archive

Completed or expired harness projects are archived to `~/.claude-gateway-archives/`. Each archive has a UUID and contains the full `.harness/` directory (tasks.json, progress.md, config.json, requirements.md, design.md, reports/).

- **Index file:** `~/.claude-gateway-archives/index.json` — lists all archived projects with UUID, project_name, chat_id, archived_at, status (complete/incomplete), and task counts.
- **Archive contents:** `~/.claude-gateway-archives/{uuid}/.harness/` — full snapshot of the project's harness state at the time of archival.

When referencing past work or looking up historical project data, read the index file first, then access the specific archive by UUID.

## Execute Loop

**PRE-FLIGHT CHECK**: Before entering the loop, verify Centurion resource data is available. Centurion operates in two modes:

- **Headless mode (primary, Telegram Bot Mode):** The backend pre-queries Centurion and injects `[Centurion Status]` into your context. Look for this block in your injected context. If present, use those values directly — do NOT run curl.
- **Interactive mode (secondary, local):** If no `[Centurion Status]` block is in your context, query Centurion yourself via curl.

If neither source provides Centurion data, **do NOT start the loop**. Tell the user: "Centurion is required for subagent scheduling. Please start Centurion first."

This is the core harness loop. Follow this algorithm precisely:

```
CONSTANTS:
  MAX_RETRIES = 3
  MAX_STALE_ROUNDS = 2
  MAX_ITERATIONS = 50
  MAX_PARALLEL = 4

STATE:
  stale_count = 0
  iteration = 0
  max_batch_size = 8
  previous_batch_size = 1    # progressive ramp-up tracker (starts at 1)

LOOP:
  0. Memory checkpoint via Centurion (run BEFORE every iteration):
     **MANDATORY**: All subagent scheduling MUST go through Centurion. Do NOT use vm_stat
     or memory_pressure as fallbacks.

     a. Obtain Centurion resource state (choose ONE path):

        **Path 1 — Headless (check context first):**
        If your context contains a `[Centurion Status]` block (injected by the bot backend),
        parse `recommended_max_agents`, `active_agents`, and `memory_pressure` from it.
        Skip curl — the data is already available.

        **Path 2 — Interactive (curl fallback):**
        If NO `[Centurion Status]` block is in your context, query directly:
        ```bash
        curl -s --connect-timeout 2 --max-time 3 \
          http://localhost:${CENTURION_PORT:-8100}/api/centurion/hardware
        ```
        - If curl **fails** (connection refused, timeout, non-JSON):
          **STOP the loop**. Tell the user:
          "Centurion is not running at localhost:${CENTURION_PORT:-8100}.
          Harness loop requires Centurion for subagent scheduling.
          Please start Centurion before continuing."
          BREAK — do NOT fall back to vm_stat or memory_pressure.

     b. Using the Centurion data (from either path):
        - `recommended_max_agents` and `active_agents` → compute max_batch_size as:
          max_batch_size = max(1, recommended_max_agents - active_agents)
          This trusts Centurion's holistic recommendation (CPU + RAM + load) directly,
          instead of applying a separate RAM formula.
        - `memory_pressure` → use as a safety override:
          - "normal": no action
          - "warn": set max_batch_size = min(max_batch_size, 2)
          - "critical": set max_batch_size = 1, write .harness/signals/memory_pause,
            log "Critical memory pressure — pausing loop for 60s", sleep 60s,
            re-query Centurion. If still critical, BREAK with message to user.
            Otherwise, remove .harness/signals/memory_pause and continue.
        Configure the port via `CENTURION_PORT` env var (default: 8100).

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
     - Compute progressive limit: progressive_limit = min(previous_batch_size, MAX_PARALLEL)
     - Compute effective limit: effective_limit = min(len(first_batch), progressive_limit, max_batch_size)
       (memory override via max_batch_size takes precedence over progressive ramp-up)
     - batch_size = effective_limit
       Trim the batch to batch_size tasks (keep the first N by task-id order)
  6. If batch has 1 task:
     - Set status → "in_progress", write tasks.json
     - Read references/role-prompts.md for the task's phase
     - Dispatch via Agent tool with run_in_background: true (In Telegram Bot Mode: dispatch INLINE, no run_in_background)
     - Tell the user: "Working on {task.id}: {title}. You can chat with me while it runs."
     - When the background agent completes, collect its result
     - Verify acceptance criteria
     - If success: status → "done", record completed_at
       previous_batch_size = min(batch_size * 2, MAX_PARALLEL)  # double on success
     - If failure: previous_batch_size = max(1, previous_batch_size / 2); go to TASK_FAILED
  7. If batch has 2+ tasks:
     - Set all to "in_progress", write tasks.json
     - Read references/role-prompts.md for the tasks' phase
     - Dispatch via Agent tool with run_in_background: true — one subagent per task, ALL in a single message (In Telegram Bot Mode: dispatch INLINE, no run_in_background)
     - Tell the user: "Dispatched {n} tasks in parallel: {id1}, {id2}, ... You can chat with me while they run."
     - Each subagent receives: task description, acceptance criteria, output files, role prompt
     - Each subagent returns: {status, output_files, notes}
     - Subagents do NOT read or write tasks.json
     - As each background agent completes, process its result
     - Wait until ALL agents in the batch are done before proceeding
     - Update tasks.json based on results (orchestrator is sole writer)
     - For any failed tasks: go to TASK_FAILED
     - Progressive ramp-up update:
       - If ALL tasks in the batch succeeded: previous_batch_size = min(batch_size * 2, MAX_PARALLEL)
         (double the batch size for next iteration, capped at MAX_PARALLEL)
       - If ANY task in the batch failed: previous_batch_size = max(1, previous_batch_size / 2)
         (halve on failure, minimum 1)
  7a. Code Review (engineering and QA tasks only):
     - After implementer completes successfully, dispatch a REVIEW subagent (run_in_background: true)
     - Reviewer prompt: read references/review-prompts.md
     - Reviewer checks: spec compliance (did it build what was asked?) + code quality (is the code good?)
     - If reviewer finds issues: dispatch implementer again with reviewer feedback
     - Max 2 review rounds. If still failing after 2 rounds, mark done with notes about remaining issues.

TASK_FAILED:
  - retry_count += 1
  - If retry_count == 1: just retry (could be transient)
  - If retry_count == 2: dispatch a DEBUGGING subagent (read references/debugging-protocol.md)
    The debugger investigates root cause and returns a diagnosis + fix plan.
    Apply the fix plan, then retry the original task.
  - If retry_count >= MAX_RETRIES: status → "blocked", notify user
  8. Log completed tasks to .harness/progress.md
  8a. Check if a PHASE just completed (all tasks in that phase are now "done"):
     - If yes: send Telegram notification with phase summary via notify.sh
     - Include: phase name, list of completed task titles, one-line result per task
  9. Check signals:
     - If .harness/signals/stop exists → BREAK
     - If .harness/signals/pause exists → BREAK
  10. Check progress:
      - If no tasks moved to "done" this round → stale_count += 1
      - If stale_count >= MAX_STALE_ROUNDS → report to user, BREAK
      - Else → stale_count = 0
  11. iteration += 1
      If iteration >= MAX_ITERATIONS → report to user, BREAK
  12. In Telegram Bot Mode: do NOT loop. Exit with the appropriate marker after one batch.
      In normal mode: Go to step 1

COMPLETE:
  - Set metadata.current_phase → "complete"
  - Write final summary to progress.md
  - Send Telegram notification: "All {total} tasks complete! Sending final report."
  - Generate final report:
    1. Create .harness/reports/ directory
    2. Write a comprehensive report (project name, duration, phase-by-phase results,
       files created/modified, issues resolved, recommendations)
    3. Generate PDF via fpdf2 or LaTeX → .harness/reports/final-report.pdf
    4. Send the report via email using the send-email skill
  - Report to user in chat: tasks completed, files created, total time
```

## Subagent Contract

### Implementer Prompt

When dispatching an implementer subagent:

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

## TDD Protocol (engineering tasks)
If this is an engineering task, follow RED-GREEN-REFACTOR:
1. Write a failing test FIRST. Run it. Confirm it fails for the right reason.
2. Write the minimum code to make the test pass. Run it. Confirm green.
3. Refactor while keeping tests green.
If you wrote production code before a test, DELETE the production code and start over.
Read references/tdd-protocol.md for the full protocol.

## Self-Review Before Returning
Before reporting completion, verify:
- [ ] All acceptance criteria are met (check each one explicitly)
- [ ] Tests pass (run the test command)
- [ ] No files outside output_files were modified
- [ ] Code follows existing project conventions
Return: {status, files_changed, test_results, summary}
```

### Reviewer Prompt

See `references/review-prompts.md` for the full reviewer prompt template. The reviewer:
1. Reads the task spec and acceptance criteria independently
2. Reads the implementer's code changes
3. Checks spec compliance: did the code do exactly what was asked?
4. Checks code quality: naming, error handling, edge cases, test coverage
5. Returns: {verdict: "pass"|"needs_work", issues: [...]}

### Debugger Prompt

See `references/debugging-protocol.md`. The debugger:
1. Reads the error output and task context
2. Investigates root cause (does NOT guess — reads code, checks logs)
3. Returns: {root_cause, fix_plan, confidence}

## Discipline: Do Not Skip Steps

These are the red flags that indicate the process is being violated:

| Red Flag | What's Happening | Correct Action |
|----------|-----------------|----------------|
| "Let me just quickly implement this" | Skipping design review | Go back to Step 2.5 |
| Writing code without a failing test | Skipping TDD RED phase | Delete the code, write the test first |
| "The test is obvious, I'll add it after" | TDD violation | The test is never obvious. Write it first. |
| "This task is too small for review" | Skipping code review | Every engineering task gets reviewed. No exceptions. |
| "I'll fix that in the next task" | Deferring known issues | Fix it now or create a tracked task for it |
| Retrying a failed task without investigation | Skipping debugging protocol | On retry_count >= 2, dispatch debugger first |

If you catch yourself rationalizing why a step can be skipped, that is the strongest signal that the step is needed.

## Additional References

- Detailed workflow documentation: read `references/workflow.md`
- Task JSON schema and rules: read `references/task-schema.md`
- Role-specific focus prompts: read `references/role-prompts.md`
- Worker protocol and signals: read `references/worker-protocol.md`
- TDD protocol for engineering tasks: read `references/tdd-protocol.md`
- Code review prompt templates: read `references/review-prompts.md`
- Systematic debugging protocol: read `references/debugging-protocol.md`
- Validate DAG: run `python <skill-dir>/scripts/validate-tasks.py .harness/tasks.json`
- Check status: run `bash <skill-dir>/scripts/status.sh`
