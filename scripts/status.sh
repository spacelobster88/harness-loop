#!/usr/bin/env bash
# Quick status summary from .harness/tasks.json
set -euo pipefail

HARNESS_DIR=".harness"

if [ ! -f "$HARNESS_DIR/tasks.json" ]; then
  echo "❌ No tasks.json found. Run /harness-loop first."
  exit 1
fi

python3 << 'PYEOF'
import json
from datetime import datetime, timezone

with open(".harness/tasks.json") as f:
    data = json.load(f)

meta = data.get("metadata", {})
tasks = data.get("tasks", [])

# Counts by status
counts = {}
for t in tasks:
    s = t["status"]
    counts[s] = counts.get(s, 0) + 1

total = len(tasks)
done = counts.get("done", 0)
pending = counts.get("pending", 0)
in_progress = counts.get("in_progress", 0)
blocked = counts.get("blocked", 0)

# Counts by phase
phases = {}
for t in tasks:
    p = t["phase"]
    if p not in phases:
        phases[p] = {"done": 0, "total": 0}
    phases[p]["total"] += 1
    if t["status"] == "done":
        phases[p]["done"] += 1

# Progress bar
if total > 0:
    pct = int(done / total * 100)
    filled = int(pct / 5)
    bar = "█" * filled + "░" * (20 - filled)
else:
    pct = 0
    bar = "░" * 20

print(f"Project: {meta.get('project_name', '(unnamed)')}")
print(f"Phase:   {meta.get('current_phase', 'unknown')}")
print()
print(f"Progress: {bar} {pct}% ({done}/{total})")
print()

# Status breakdown
print("Status:")
for status, icon in [("done", "✅"), ("in_progress", "🔄"), ("pending", "⏳"), ("blocked", "🚫")]:
    if counts.get(status, 0) > 0:
        print(f"  {icon} {status}: {counts[status]}")

print()
print("Phases:")
phase_order = ["architecture", "uiux", "engineering", "qa"]
for p in phase_order:
    if p in phases:
        d = phases[p]["done"]
        t = phases[p]["total"]
        check = "✅" if d == t else "🔄" if d > 0 else "⏳"
        print(f"  {check} {p}: {d}/{t}")

# Worker status
import os
if os.path.exists(".harness/worker.pid"):
    try:
        pid = int(open(".harness/worker.pid").read().strip())
        os.kill(pid, 0)  # check if running
        print(f"\nWorker: running (PID {pid})")
    except (ProcessLookupError, ValueError):
        print("\nWorker: not running (stale PID file)")
else:
    print("\nWorker: not running")

# Signals
if os.path.exists(".harness/signals/pause"):
    print("Signal: ⏸️  PAUSE active")
if os.path.exists(".harness/signals/stop"):
    print("Signal: 🛑 STOP active")

# Blocked tasks detail
blocked_tasks = [t for t in tasks if t["status"] == "blocked"]
if blocked_tasks:
    print("\nBlocked tasks:")
    for t in blocked_tasks:
        print(f"  🚫 {t['id']}: {t['title']} (retries: {t.get('retry_count', 0)})")
        if t.get("notes"):
            print(f"     Note: {t['notes']}")
PYEOF
