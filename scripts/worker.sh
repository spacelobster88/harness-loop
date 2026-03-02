#!/usr/bin/env bash
# Launch the harness-loop background worker
# Usage: bash worker.sh [--foreground]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_DIR=".harness"
WORKER_LOG="$HARNESS_DIR/worker.log"

# Validate state
if [ ! -d "$HARNESS_DIR" ]; then
  echo "❌ No .harness/ directory. Run /harness-loop first."
  exit 1
fi

if [ ! -f "$HARNESS_DIR/tasks.json" ]; then
  echo "❌ No tasks.json found. Generate a task DAG first."
  exit 1
fi

# Check for existing worker
if [ -f "$HARNESS_DIR/worker.pid" ]; then
  OLD_PID=$(cat "$HARNESS_DIR/worker.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "⚠️  Worker already running (PID $OLD_PID). Use /harness-loop stop first."
    exit 1
  fi
  rm -f "$HARNESS_DIR/worker.pid"
fi

# Clear signals
rm -f "$HARNESS_DIR/signals/pause" "$HARNESS_DIR/signals/stop"

# Count pending tasks
if command -v python3 &>/dev/null; then
  PENDING=$(python3 -c "
import json
with open('$HARNESS_DIR/tasks.json') as f:
    data = json.load(f)
pending = sum(1 for t in data['tasks'] if t['status'] in ('pending', 'in_progress'))
print(pending)
")
else
  PENDING="?"
fi

# Send start notification
bash "$SCRIPT_DIR/notify.sh" "▶️ Harness worker started ($PENDING tasks pending)" 2>/dev/null || true

# Build the worker prompt
WORKER_PROMPT=$(cat "$SKILL_DIR/worker/WORKER_PROMPT.md")

# Append current tasks.json content for context
TASKS_CONTENT=$(cat "$HARNESS_DIR/tasks.json")
FULL_PROMPT="$WORKER_PROMPT

## Current tasks.json
\`\`\`json
$TASKS_CONTENT
\`\`\`

Begin execution now. Follow the execute loop algorithm. The project root is: $(pwd)"

if [ "${1:-}" = "--foreground" ]; then
  echo "🔧 Running worker in foreground (PID $$)..."
  echo $$ > "$HARNESS_DIR/worker.pid"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] STARTED worker (foreground, PID $$)" >> "$WORKER_LOG"

  claude -p --dangerously-skip-permissions --output-format text "$FULL_PROMPT" 2>&1 | tee -a "$WORKER_LOG"

  rm -f "$HARNESS_DIR/worker.pid"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] EXITED worker" >> "$WORKER_LOG"
else
  echo "🚀 Launching worker in background..."
  nohup bash -c "
    echo \$\$ > '$HARNESS_DIR/worker.pid'
    echo \"[\$(date -u +'%Y-%m-%dT%H:%M:%SZ')] STARTED worker (background, PID \$\$)\" >> '$WORKER_LOG'
    claude -p --dangerously-skip-permissions --output-format text '$FULL_PROMPT' >> '$WORKER_LOG' 2>&1
    rm -f '$HARNESS_DIR/worker.pid'
    echo \"[\$(date -u +'%Y-%m-%dT%H:%M:%SZ')] EXITED worker\" >> '$WORKER_LOG'
  " &>/dev/null &

  sleep 1
  if [ -f "$HARNESS_DIR/worker.pid" ]; then
    PID=$(cat "$HARNESS_DIR/worker.pid")
    echo "✅ Worker started (PID $PID)"
    echo "   Log: $WORKER_LOG"
    echo "   Use /harness-loop status to check progress"
    echo "   Use /harness-loop pause to pause"
  else
    echo "⚠️  Worker may not have started. Check $WORKER_LOG"
  fi
fi
