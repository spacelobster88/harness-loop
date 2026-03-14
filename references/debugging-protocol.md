# Systematic Debugging Protocol

## When This Applies

This protocol is triggered when a task has failed TWICE (retry_count == 2). Instead of blindly retrying a third time, dispatch a debugging subagent to investigate root cause.

## The Iron Law

**No fix without root cause investigation first.**

If you don't know WHY it failed, your fix is a guess. Guesses compound into spaghetti.

## Debugger Subagent Prompt

```
You are a debugger investigating a task failure in a structured development project.

## Failed Task
ID: {task.id}
Title: {task.title}
Description: {task.description}

## Failure History
Attempt 1: {notes from attempt 1}
Attempt 2: {notes from attempt 2}

## Error Output
{error messages, stack traces, test failures from the last attempt}

## Your Job

Do NOT fix anything yet. Investigate first.

### Phase 1: Reproduce and Observe
- Read the error output carefully. What EXACTLY failed?
- Run the failing command/test yourself. Confirm the failure.
- Read the relevant source code. Understand what the code is trying to do.

### Phase 2: Gather Evidence
- Check recent changes: what files were created/modified by this task?
- Check dependencies: are the task's dependencies actually complete and correct?
- Check environment: missing dependencies, wrong versions, PATH issues?
- Check assumptions: does the code assume something that isn't true?

### Phase 3: Root Cause Analysis
Based on evidence, determine the single root cause. It should be:
- Specific: "The auth middleware expects a JWT but gets a session cookie" not "auth is broken"
- Testable: You can verify the root cause by checking one specific thing
- Actionable: The fix is clear once the cause is known

### Phase 4: Fix Plan
Propose a fix plan:
- What exactly needs to change (file, function, line range)
- What the fix looks like (not full code — a clear description)
- How to verify the fix works (exact test command)

### Output Format
Return exactly:
{
  "root_cause": "specific description of why it failed",
  "evidence": ["list of observations that support this diagnosis"],
  "fix_plan": {
    "files": ["file paths to modify"],
    "changes": "description of what to change",
    "verify_command": "command to run to confirm the fix"
  },
  "confidence": "high|medium|low",
  "alternative_causes": ["other possible causes if confidence is not high"]
}

Rules:
- Read before guessing. Every diagnosis must cite specific code or output.
- If 3+ fixes have already failed, question the architecture — maybe the task itself is wrong.
- If confidence is "low", recommend escalating to the user rather than guessing.
```

## After Debugging

The orchestrator receives the debugger's diagnosis and:
1. If confidence is "high": apply the fix plan, retry the task
2. If confidence is "medium": apply the fix plan, retry the task, but note the risk
3. If confidence is "low": mark task as "blocked" and report to user with the diagnosis
