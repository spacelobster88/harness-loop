# Workflow Reference

## Phase Lifecycle

Each phase has entry conditions, actions, and exit conditions.

### Requirements Phase
- **Entry**: No `.harness/requirements.md` content, or user requests re-scoping
- **Actions**: Interactive Q&A with user, capture in requirements.md
- **Exit**: User approves requirements summary
- **Next**: Design Brainstorming

### Design Brainstorming Phase
- **Entry**: Requirements approved
- **Actions**: Explore codebase context, propose 2-3 approaches with trade-offs, write `.harness/design.md`
- **Exit**: User explicitly approves the design ("looks good", "approved", etc.)
- **HARD GATE**: No task decomposition or implementation until design is approved
- **Next**: Task Decomposition → Architecture

### Architecture Phase
- **Entry**: Task DAG exists with `arch-*` tasks in `pending` status
- **Actions**: Execute arch tasks (design docs, API specs, schemas, ADRs)
- **Exit**: All `arch-*` tasks are `done`
- **Next**: UI/UX (or Engineering if no uiux tasks)

### UI/UX Phase
- **Entry**: Architecture tasks that this phase depends on are `done`
- **Actions**: Execute uiux tasks (wireframes, component specs, user flows)
- **Exit**: All `uiux-*` tasks are `done`
- **Next**: Engineering
- **Note**: UI/UX tasks may run in parallel with late architecture tasks if no dependency exists

### Engineering Phase
- **Entry**: Relevant arch and uiux dependencies are `done`
- **Actions**: Execute eng tasks (write source code, configs, build scripts)
- **Exit**: All `eng-*` tasks are `done`
- **Next**: QA

### QA Phase
- **Entry**: Relevant eng dependencies are `done`
- **Actions**: Execute qa tasks (write tests, run tests, validate criteria)
- **Exit**: All `qa-*` tasks are `done`
- **Next**: Completion
- **Special**: QA may generate new `eng-*` tasks for non-trivial bugs. These are inserted into the DAG with correct dependencies. The harness loop naturally picks them up.

### Completion
- **Entry**: All tasks in all phases are `done`
- **Actions**: Generate summary, update metadata, notify user
- **Exit**: `metadata.current_phase` = `"complete"`

## Edge Cases

### User wants to skip a phase
Mark all tasks in that phase as `done` with `notes: "Skipped by user"`. The harness loop will proceed to the next phase.

### User adds requirements mid-build
1. Append to `.harness/requirements.md`
2. Generate new tasks for the added requirements
3. Add them to `tasks.json` with appropriate dependencies
4. Run `validate-tasks.py` to ensure DAG integrity
5. The harness loop picks up new tasks automatically

### Single-task project
The DAG can have just one task. The harness loop still works — it just completes in one iteration.

### Non-web projects (CLI tool, backend service, reports, dashboards)
The uiux phase is still required — every project has a presentation layer. For CLI tools, design output formatting and progress indicators. For reports/PDFs, design page layout, typography, and data visualization. For dashboards, design card layouts and metric presentation. For APIs, design developer documentation layout. See `references/role-prompts.md` for the UI/UX Agent's full design philosophy.

### QA finds a critical bug
This is handled **automatically** by step 7b in the Execute Loop:

1. QA agent returns a structured bug report (JSON with `"bugs": [...]`)
2. The orchestrator auto-creates `eng-fix-*` tasks from the bug reports
3. The `qa-*` task gets the new eng-fix tasks added as dependencies and resets to `pending`
4. The harness loop executes the fixes, then re-runs the QA task

**Convergence limits** prevent endless loops:
- `MAX_QA_CYCLES = 3`: each qa task can trigger at most 3 fix-and-retest cycles
- `MAX_REWORK_TASKS = 8`: total eng-fix tasks across the project are capped
- After limits are hit, remaining bugs become "known issues" in the final report

## Parallel Execution Rules

### Batch Formation
1. Collect all ready tasks (pending + all deps done)
2. Build conflict graph: edge between tasks that share `output_files`
3. Find maximum independent set (greedy: sort by phase priority, then ID)
4. That set = one parallel batch
5. Remaining ready tasks wait for next round

### Phase Priority Order
When multiple phases have ready tasks, execute in this order:
1. Architecture (highest priority — unblocks everything)
2. UI/UX
3. Engineering
4. QA (lowest priority — depends on everything)

Within the same phase, lower-numbered IDs go first: `eng-1` before `eng-3`.

## Context Window Management

Long-running harness loops may approach context limits. Strategies:
- Each task is self-contained: read task description + criteria, execute, done
- `progress.md` serves as compressed history for resume
- If context grows large, user can `/compact` then `/harness-loop resume`
- Background worker naturally manages context via `claude -p` (fresh context per invocation)
