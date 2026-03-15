#!/usr/bin/env bash
# Initialize .harness/ directory for a new project
set -euo pipefail

HARNESS_DIR=".harness"

ARCHIVE_BASE="$HOME/.claude-gateway-archives"

if [ -d "$HARNESS_DIR" ]; then
  echo "📦 Archiving existing .harness/ directory..."

  ARCHIVE_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  ARCHIVE_DIR="$ARCHIVE_BASE/$ARCHIVE_UUID"
  mkdir -p "$ARCHIVE_DIR"

  # Copy the entire .harness/ into the archive
  cp -R "$HARNESS_DIR" "$ARCHIVE_DIR/.harness"

  # Extract metadata from tasks.json for the index entry
  PROJ_NAME=""
  TASKS_DONE=0
  TASKS_TOTAL=0
  ARCHIVE_STATUS="incomplete"
  if [ -f "$HARNESS_DIR/tasks.json" ] && command -v python3 &>/dev/null; then
    PROJ_NAME=$(python3 -c "
import json, sys
try:
    d = json.load(open('$HARNESS_DIR/tasks.json'))
    print(d.get('metadata', {}).get('project_name', ''))
except: pass
" 2>/dev/null || true)
    read -r TASKS_DONE TASKS_TOTAL <<< "$(python3 -c "
import json
try:
    d = json.load(open('$HARNESS_DIR/tasks.json'))
    tasks = d.get('tasks', [])
    total = len(tasks)
    done = sum(1 for t in tasks if t.get('status') == 'done')
    print(done, total)
except: print('0 0')
" 2>/dev/null || echo "0 0")"
    if [ "$TASKS_TOTAL" -gt 0 ] && [ "$TASKS_DONE" -eq "$TASKS_TOTAL" ]; then
      ARCHIVE_STATUS="complete"
    fi
  fi

  # Extract chat_id from config.json if available
  CHAT_ID=""
  if [ -f "$HARNESS_DIR/config.json" ] && command -v python3 &>/dev/null; then
    CHAT_ID=$(python3 -c "
import json
try:
    d = json.load(open('$HARNESS_DIR/config.json'))
    print(d.get('chat_id', ''))
except: pass
" 2>/dev/null || true)
  fi

  # Timestamp for archive
  if command -v python3 &>/dev/null; then
    ARCHIVE_TS=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())")
  else
    ARCHIVE_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fi

  # Append entry to index.json
  INDEX_FILE="$ARCHIVE_BASE/index.json"
  if [ ! -f "$INDEX_FILE" ]; then
    echo '[]' > "$INDEX_FILE"
  fi

  python3 -c "
import json
entry = {
    'uuid': '$ARCHIVE_UUID',
    'project_name': '$PROJ_NAME',
    'chat_id': '$CHAT_ID',
    'archived_at': '$ARCHIVE_TS',
    'status': '$ARCHIVE_STATUS',
    'tasks_done': $TASKS_DONE,
    'tasks_total': $TASKS_TOTAL
}
with open('$INDEX_FILE', 'r') as f:
    index = json.load(f)
index.append(entry)
with open('$INDEX_FILE', 'w') as f:
    json.dump(index, f, indent=2)
"

  # Remove old .harness/
  rm -rf "$HARNESS_DIR"

  echo "✅ Archived to $ARCHIVE_DIR"
fi

mkdir -p "$HARNESS_DIR/signals"

# Config
cat > "$HARNESS_DIR/config.json" << 'EOF'
{
  "created_at": "",
  "project_name": "",
  "execution_mode": ""
}
EOF
# Stamp the creation time
if command -v python3 &>/dev/null; then
  TS=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())")
else
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
# Use portable sed
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/\"created_at\": \"\"/\"created_at\": \"$TS\"/" "$HARNESS_DIR/config.json"
else
  sed -i "s/\"created_at\": \"\"/\"created_at\": \"$TS\"/" "$HARNESS_DIR/config.json"
fi

# Empty tasks file
cat > "$HARNESS_DIR/tasks.json" << EOF
{
  "metadata": {
    "project_name": "",
    "created_at": "$TS",
    "updated_at": "$TS",
    "current_phase": "init",
    "telegram_chat_id": "",
    "telegram_bot_token_env": "HARNESS_TG_TOKEN"
  },
  "tasks": []
}
EOF

# Requirements placeholder
cat > "$HARNESS_DIR/requirements.md" << 'EOF'
# Requirements

*Captured during requirements gathering phase.*
EOF

# Progress log
cat > "$HARNESS_DIR/progress.md" << EOF
# Progress Log

## $(date -u +"%Y-%m-%d")
- Project initialized
EOF

# Add to .gitignore if not already there
if [ -f ".gitignore" ]; then
  if ! grep -q "^\.harness/" ".gitignore" 2>/dev/null; then
    echo "" >> ".gitignore"
    echo "# Harness loop state" >> ".gitignore"
    echo ".harness/" >> ".gitignore"
  fi
else
  cat > ".gitignore" << 'GITEOF'
# Harness loop state
.harness/
GITEOF
fi

echo "✅ Initialized .harness/ directory"
echo "   config.json  — project metadata"
echo "   tasks.json   — task DAG (empty)"
echo "   requirements.md — requirements placeholder"
echo "   progress.md  — progress log"
echo "   signals/     — control signals directory"
