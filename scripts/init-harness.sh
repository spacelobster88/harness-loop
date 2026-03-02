#!/usr/bin/env bash
# Initialize .harness/ directory for a new project
set -euo pipefail

HARNESS_DIR=".harness"

if [ -d "$HARNESS_DIR" ]; then
  echo "⚠️  .harness/ already exists. Use /harness-loop to resume."
  exit 1
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
