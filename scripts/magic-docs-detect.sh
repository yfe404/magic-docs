#!/usr/bin/env bash
# magic-docs-detect.sh — UserPromptSubmit + PostToolUse hook for Claude Code
# Scans the project for files with "# MAGIC DOC:" header and tracks them.

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty') || exit 0

[ -n "$SESSION_ID" ] && [ -n "$CWD" ] || exit 0

TRACK="/tmp/magic-docs-${SESSION_ID}.txt"

if [ "$EVENT" = "UserPromptSubmit" ]; then
  # Scan the project for all magic doc files
  while IFS= read -r file; do
    grep -qxF "$file" "$TRACK" 2>/dev/null || echo "$file" >> "$TRACK"
  done < <(grep -rl '^# *MAGIC *DOC:' "$CWD" --include='*.md' 2>/dev/null || true)

elif [ "$EVENT" = "PostToolUse" ]; then
  # Also catch files read by the Read tool outside the project
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
  [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] || exit 0
  FIRST_LINE=$(head -1 "$FILE_PATH" 2>/dev/null) || exit 0
  if echo "$FIRST_LINE" | grep -qi '# *MAGIC *DOC:'; then
    grep -qxF "$FILE_PATH" "$TRACK" 2>/dev/null || echo "$FILE_PATH" >> "$TRACK"
  fi
fi

exit 0
