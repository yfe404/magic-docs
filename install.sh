#!/usr/bin/env bash
# install.sh — Install Magic Docs hooks and skill for Claude Code
#
# This script:
#   1. Checks for required dependencies (jq)
#   2. Copies hook scripts to ~/.claude/scripts/
#   3. Copies the skill to ~/.claude/skills/
#   4. Merges hook configuration into ~/.claude/settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
SKILLS_DIR="${CLAUDE_DIR}/skills"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# ── Check dependencies ──────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  error "jq is required but not installed. Install it with your package manager:
    Arch:   sudo pacman -S jq
    Debian: sudo apt install jq
    macOS:  brew install jq"
fi

if ! command -v flock >/dev/null 2>&1; then
  warn "flock not found (standard on Linux, optional on macOS). Script will work without it but may have rare race conditions with concurrent file reads."
fi

# ── Create directories ──────────────────────────────────────────────────────

mkdir -p "$SCRIPTS_DIR"
mkdir -p "$SKILLS_DIR"

# ── Copy scripts ────────────────────────────────────────────────────────────

cp "$SCRIPT_DIR/scripts/magic-docs-detect.sh" "$SCRIPTS_DIR/"
cp "$SCRIPT_DIR/scripts/magic-docs-stop.sh" "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR/magic-docs-detect.sh"
chmod +x "$SCRIPTS_DIR/magic-docs-stop.sh"
info "Installed hook scripts to $SCRIPTS_DIR/"

# ── Copy skill ──────────────────────────────────────────────────────────────

cp "$SCRIPT_DIR/skills/update-docs.md" "$SKILLS_DIR/"
info "Installed /update-docs skill to $SKILLS_DIR/"

# ── Merge hooks into settings.json ──────────────────────────────────────────

HOOKS_CONFIG='{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "'"$SCRIPTS_DIR"'/magic-docs-detect.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'"$SCRIPTS_DIR"'/magic-docs-stop.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}'

if [ -f "$SETTINGS_FILE" ]; then
  # Merge hooks into existing settings (preserves other keys)
  EXISTING=$(cat "$SETTINGS_FILE")

  # Check if hooks already exist
  if echo "$EXISTING" | jq -e '.hooks.PostToolUse' >/dev/null 2>&1 || \
     echo "$EXISTING" | jq -e '.hooks.Stop' >/dev/null 2>&1; then
    warn "Existing hooks detected in $SETTINGS_FILE"
    warn "Please manually merge the following hook configuration:"
    echo ""
    echo "$HOOKS_CONFIG" | jq '.hooks'
    echo ""
    warn "You can add these entries to your existing hooks.PostToolUse and hooks.Stop arrays."
  else
    # Safe to merge — no existing hook keys conflict
    echo "$EXISTING" | jq --argjson hooks "$(echo "$HOOKS_CONFIG" | jq '.hooks')" \
      '.hooks = ($hooks + (.hooks // {}))' > "$SETTINGS_FILE"
    info "Merged hook configuration into $SETTINGS_FILE"
  fi
else
  # Create new settings file
  echo "$HOOKS_CONFIG" | jq '.' > "$SETTINGS_FILE"
  info "Created $SETTINGS_FILE with hook configuration"
fi

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
info "Magic Docs installed successfully!"
echo ""
echo "  Usage:"
echo "    1. Add '# MAGIC DOC: Your Title' as the first line of any .md file"
echo "    2. Optionally add an italicized instruction line below the header:"
echo "       *Focus on API design decisions and integration patterns*"
echo "    3. When Claude reads that file during a conversation, it will"
echo "       automatically update it with new learnings when the turn ends"
echo ""
echo "  Manual update:"
echo "    Run /update-docs in Claude Code to update all magic docs on demand"
echo ""
echo "  Uninstall:"
echo "    rm $SCRIPTS_DIR/magic-docs-detect.sh"
echo "    rm $SCRIPTS_DIR/magic-docs-stop.sh"
echo "    rm $SKILLS_DIR/update-docs.md"
echo "    Remove the hooks entries from $SETTINGS_FILE"
