#!/usr/bin/env python3
"""Validate a harness-loop tasks.json file.

Checks:
  - JSON schema validity
  - No duplicate task IDs
  - All dependencies reference existing tasks
  - No dependency cycles (topological sort)
  - No output_files overlap between tasks without dependency
  - Task ID format matches phase prefix
  - Acceptance criteria are non-empty

Usage:
  python validate-tasks.py .harness/tasks.json
  python validate-tasks.py --test   # run built-in tests
"""
import json
import sys
from collections import defaultdict

VALID_STATUSES = {"pending", "in_progress", "done", "blocked"}
VALID_PHASES = {"architecture", "uiux", "engineering", "qa"}
PHASE_PREFIXES = {"architecture": "arch", "uiux": "uiux", "engineering": "eng", "qa": "qa"}


def validate(data: dict) -> list[str]:
    """Validate tasks.json data. Returns list of error strings (empty = valid)."""
    errors = []
    warnings = []

    # Top-level structure
    if "metadata" not in data:
        errors.append("Missing 'metadata' key")
    if "tasks" not in data:
        errors.append("Missing 'tasks' key")
        return errors

    tasks = data["tasks"]
    if not isinstance(tasks, list):
        errors.append("'tasks' must be an array")
        return errors

    # Build lookup
    task_map = {}
    for t in tasks:
        tid = t.get("id", "<missing>")

        # Duplicate check
        if tid in task_map:
            errors.append(f"Duplicate task ID: {tid}")
        task_map[tid] = t

        # Required fields
        for field in ["id", "title", "description", "phase", "status", "dependencies",
                       "acceptance_criteria", "output_files"]:
            if field not in t:
                errors.append(f"{tid}: missing required field '{field}'")

        # Status enum
        status = t.get("status", "")
        if status not in VALID_STATUSES:
            errors.append(f"{tid}: invalid status '{status}' (must be one of {VALID_STATUSES})")

        # Phase enum
        phase = t.get("phase", "")
        if phase not in VALID_PHASES:
            errors.append(f"{tid}: invalid phase '{phase}' (must be one of {VALID_PHASES})")

        # ID prefix matches phase
        if phase in PHASE_PREFIXES:
            expected_prefix = PHASE_PREFIXES[phase] + "-"
            if not tid.startswith(expected_prefix):
                errors.append(f"{tid}: ID should start with '{expected_prefix}' for phase '{phase}'")

        # Acceptance criteria non-empty
        criteria = t.get("acceptance_criteria", [])
        if not criteria:
            errors.append(f"{tid}: acceptance_criteria must not be empty")

        # Output files
        output_files = t.get("output_files", [])
        if not output_files:
            warnings.append(f"{tid}: no output_files specified (warning)")

    # Dependency existence
    for t in tasks:
        tid = t.get("id", "")
        for dep in t.get("dependencies", []):
            if dep not in task_map:
                errors.append(f"{tid}: dependency '{dep}' does not exist")

    # Cycle detection via topological sort (Kahn's algorithm)
    in_degree = defaultdict(int)
    adjacency = defaultdict(list)
    all_ids = set(task_map.keys())

    for t in tasks:
        tid = t["id"]
        in_degree.setdefault(tid, 0)
        for dep in t.get("dependencies", []):
            if dep in all_ids:
                adjacency[dep].append(tid)
                in_degree[tid] += 1

    queue = [tid for tid in all_ids if in_degree[tid] == 0]
    sorted_count = 0

    while queue:
        node = queue.pop(0)
        sorted_count += 1
        for neighbor in adjacency[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    if sorted_count != len(all_ids):
        cycle_tasks = [tid for tid in all_ids if in_degree[tid] > 0]
        errors.append(f"Dependency cycle detected involving: {', '.join(sorted(cycle_tasks))}")

    # Output file overlap without dependency
    file_to_tasks = defaultdict(list)
    for t in tasks:
        for f in t.get("output_files", []):
            file_to_tasks[f].append(t["id"])

    for filepath, tids in file_to_tasks.items():
        if len(tids) > 1:
            # Check all pairs have a dependency path
            for i in range(len(tids)):
                for j in range(i + 1, len(tids)):
                    if not _has_dependency_path(tids[i], tids[j], task_map) and \
                       not _has_dependency_path(tids[j], tids[i], task_map):
                        errors.append(
                            f"Output file '{filepath}' shared by {tids[i]} and {tids[j]} "
                            f"without dependency between them"
                        )

    # Orphan detection (warning only)
    depended_on = set()
    has_deps = set()
    for t in tasks:
        if t.get("dependencies"):
            has_deps.add(t["id"])
        for dep in t.get("dependencies", []):
            depended_on.add(dep)

    for tid in all_ids:
        if tid not in depended_on and tid not in has_deps:
            warnings.append(f"{tid}: orphan task (no dependencies and not depended on)")

    # Print warnings
    for w in warnings:
        print(f"  ⚠️  {w}")

    return errors


def _has_dependency_path(source: str, target: str, task_map: dict) -> bool:
    """Check if there's a dependency path from source to target (target depends on source)."""
    visited = set()
    stack = [target]
    while stack:
        current = stack.pop()
        if current == source:
            return True
        if current in visited:
            continue
        visited.add(current)
        task = task_map.get(current, {})
        stack.extend(task.get("dependencies", []))
    return False


def run_tests():
    """Run built-in validation tests."""
    passed = 0
    failed = 0

    def assert_valid(name, data):
        nonlocal passed, failed
        errs = validate(data)
        if errs:
            print(f"  ❌ {name}: expected valid, got errors:")
            for e in errs:
                print(f"     {e}")
            failed += 1
        else:
            print(f"  ✅ {name}")
            passed += 1

    def assert_error(name, data, expected_substring):
        nonlocal passed, failed
        errs = validate(data)
        matching = [e for e in errs if expected_substring in e]
        if matching:
            print(f"  ✅ {name}")
            passed += 1
        else:
            print(f"  ❌ {name}: expected error containing '{expected_substring}', got: {errs}")
            failed += 1

    def make_task(tid="arch-1", phase="architecture", status="pending",
                  deps=None, criteria=None, files=None):
        return {
            "id": tid, "title": f"Task {tid}", "description": f"Do {tid}",
            "phase": phase, "status": status,
            "dependencies": deps if deps is not None else [],
            "acceptance_criteria": criteria if criteria is not None else ["Criterion 1"],
            "output_files": files if files is not None else [f"output/{tid}.md"],
            "retry_count": 0
        }

    def wrap(tasks):
        return {"metadata": {"project_name": "test", "current_phase": "architecture"}, "tasks": tasks}

    print("\nRunning validation tests...\n")

    # 1. Valid linear chain
    assert_valid("Valid linear chain", wrap([
        make_task("arch-1", "architecture", files=["docs/api.md"]),
        make_task("eng-1", "engineering", deps=["arch-1"], files=["src/app.ts"]),
        make_task("qa-1", "qa", deps=["eng-1"], files=["tests/app.test.ts"]),
    ]))

    # 2. Cyclic DAG
    assert_error("Cyclic DAG", wrap([
        make_task("arch-1", deps=["qa-1"]),
        make_task("eng-1", "engineering", deps=["arch-1"], files=["src/b.ts"]),
        make_task("qa-1", "qa", deps=["eng-1"], files=["tests/c.ts"]),
    ]), "cycle detected")

    # 3. Empty DAG
    assert_valid("Empty DAG", wrap([]))

    # 4. Missing dependency
    assert_error("Missing dependency", wrap([
        make_task("eng-1", "engineering", deps=["arch-99"]),
    ]), "does not exist")

    # 5. File overlap without dep
    assert_error("File overlap no dep", wrap([
        make_task("eng-1", "engineering", files=["src/app.ts"]),
        make_task("eng-2", "engineering", files=["src/app.ts"]),
    ]), "without dependency")

    # 6. File overlap with dep
    assert_valid("File overlap with dep", wrap([
        make_task("eng-1", "engineering", files=["src/app.ts"]),
        make_task("eng-2", "engineering", deps=["eng-1"], files=["src/app.ts"]),
    ]))

    # 7. Invalid status
    assert_error("Invalid status", wrap([
        make_task("arch-1", status="running"),
    ]), "invalid status")

    # 8. Empty criteria
    assert_error("Empty criteria", wrap([
        make_task("arch-1", criteria=[]),
    ]), "must not be empty")

    # 9. ID prefix mismatch
    assert_error("ID prefix mismatch", wrap([
        make_task("eng-1", phase="architecture"),
    ]), "should start with")

    # 10. Duplicate ID
    assert_error("Duplicate ID", wrap([
        make_task("arch-1"),
        make_task("arch-1"),
    ]), "Duplicate")

    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed")
    return failed == 0


def main():
    if len(sys.argv) < 2:
        print("Usage: validate-tasks.py <tasks.json>")
        print("       validate-tasks.py --test")
        sys.exit(1)

    if sys.argv[1] == "--test":
        success = run_tests()
        sys.exit(0 if success else 1)

    filepath = sys.argv[1]
    try:
        with open(filepath) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"❌ File not found: {filepath}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON: {e}")
        sys.exit(1)

    errors = validate(data)
    if errors:
        print(f"❌ Validation failed ({len(errors)} errors):\n")
        for e in errors:
            print(f"  ❌ {e}")
        sys.exit(1)
    else:
        task_count = len(data.get("tasks", []))
        print(f"✅ Valid task DAG ({task_count} tasks)")
        sys.exit(0)


if __name__ == "__main__":
    main()
