#!/usr/bin/env bash
# Install harness-loop skill for Claude Code
# Usage:
#   ./install.sh --global    # Install to ~/.claude/skills/harness-loop/
#   ./install.sh --project   # Install to .claude/skills/harness-loop/ (current project)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 [--global|--project]"
  echo ""
  echo "  --global   Install to ~/.claude/skills/harness-loop/ (available everywhere)"
  echo "  --project  Install to .claude/skills/harness-loop/ (current project only)"
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

# Create parent directory
mkdir -p "$(dirname "$TARGET")"

# Create symlink
if [ -L "$TARGET" ]; then
  EXISTING=$(readlink "$TARGET")
  if [ "$EXISTING" = "$SCRIPT_DIR" ]; then
    echo "Already installed at $TARGET"
    exit 0
  fi
  echo "Existing symlink points to: $EXISTING"
  echo "Updating to: $SCRIPT_DIR"
  rm "$TARGET"
elif [ -d "$TARGET" ]; then
  echo "Directory exists at $TARGET (not a symlink)."
  echo "Remove it first: rm -rf $TARGET"
  exit 1
fi

ln -s "$SCRIPT_DIR" "$TARGET"
echo "Installed harness-loop skill"
echo "  $TARGET -> $SCRIPT_DIR"
echo ""
echo "Usage: In Claude Code, type /harness-loop"
