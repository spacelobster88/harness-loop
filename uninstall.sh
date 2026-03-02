#!/usr/bin/env bash
# Uninstall harness-loop skill
# Usage:
#   ./uninstall.sh --global    # Remove from ~/.claude/skills/
#   ./uninstall.sh --project   # Remove from .claude/skills/
set -euo pipefail

usage() {
  echo "Usage: $0 [--global|--project]"
  exit 1
}

MODE="${1:-}"
if [ -z "$MODE" ]; then
  usage
fi

case "$MODE" in
  --global)
    TARGET="$HOME/.claude/skills/harness-loop"
    ;;
  --project)
    TARGET=".claude/skills/harness-loop"
    ;;
  *)
    usage
    ;;
esac

if [ -L "$TARGET" ]; then
  rm "$TARGET"
  echo "Removed symlink: $TARGET"
elif [ -d "$TARGET" ]; then
  echo "$TARGET is a directory, not a symlink."
  echo "Remove manually: rm -rf $TARGET"
  exit 1
else
  echo "Nothing to remove — $TARGET does not exist"
fi
