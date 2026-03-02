#!/usr/bin/env bash
# Send a Telegram notification
# Usage: bash notify.sh "message text"
#
# Reads credentials from:
#   1. Environment: HARNESS_TG_TOKEN + HARNESS_TG_CHAT_ID
#   2. .harness/config.json (telegram_chat_id) + env token
#   3. .harness/tasks.json metadata
set -euo pipefail

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: notify.sh <message>"
  exit 1
fi

# Try environment first
TOKEN="${HARNESS_TG_TOKEN:-}"
CHAT_ID="${HARNESS_TG_CHAT_ID:-}"

# Fallback to tasks.json metadata
if [ -z "$CHAT_ID" ] && [ -f ".harness/tasks.json" ]; then
  if command -v python3 &>/dev/null; then
    CHAT_ID=$(python3 -c "
import json
with open('.harness/tasks.json') as f:
    data = json.load(f)
print(data.get('metadata', {}).get('telegram_chat_id', ''))
" 2>/dev/null || true)
  fi
fi

if [ -z "$TOKEN" ]; then
  echo "⚠️  No HARNESS_TG_TOKEN set. Skipping notification."
  echo "   Message was: $MESSAGE"
  exit 0
fi

if [ -z "$CHAT_ID" ]; then
  echo "⚠️  No chat ID found. Set HARNESS_TG_CHAT_ID or add to tasks.json metadata."
  echo "   Message was: $MESSAGE"
  exit 0
fi

# Send via Telegram Bot API
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${MESSAGE}" \
  -d "parse_mode=Markdown" \
  --connect-timeout 10 \
  --max-time 15)

if [ "$HTTP_CODE" = "200" ]; then
  exit 0
else
  # Retry without parse_mode in case of markdown issues
  curl -s -o /dev/null \
    "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${MESSAGE}" \
    --connect-timeout 10 \
    --max-time 15 || true
fi
