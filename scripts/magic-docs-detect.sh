#!/usr/bin/env bash
# magic-docs-detect.sh — PostToolUse hook for Claude Code
#
# Fires after every Read tool call. Detects files with a "# MAGIC DOC:" header
# and tracks their paths in a session-scoped temp file for later processing
# by magic-docs-stop.sh.
#
# Performance target: <50ms (fires on every file read)

set -euo pipefail

INPUT=$(cat)

# Extract session_id and file_path (always present in Read hook input)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
RESPONSE_TYPE=$(echo "$INPUT" | jq -r '.tool_response.type // empty')

[ -n "$SESSION_ID" ] && [ -n "$FILE_PATH" ] || exit 0

# Determine if this file has a MAGIC DOC header.
# Two cases:
#   1. type="text" — first read, content is in tool_response.file.content
#   2. type="file_unchanged" — subsequent read, content not included (deduped)
#      In this case, read the file directly from disk
MAGIC=false

if [ "$RESPONSE_TYPE" = "text" ]; then
  # Check content from the tool response
  MAGIC=$(echo "$INPUT" | jq -r '
    if (.tool_response.file.content[0:200] | test("^#\\s*MAGIC\\s+DOC:"; "im")) then "true"
    else "false"
    end
  ')
elif [ "$RESPONSE_TYPE" = "file_unchanged" ] || [ "$RESPONSE_TYPE" = "" ]; then
  # Content not in response — check the file directly
  if [ -f "$FILE_PATH" ]; then
    FIRST_LINE=$(head -1 "$FILE_PATH" 2>/dev/null || true)
    if echo "$FIRST_LINE" | grep -qi '^# *MAGIC *DOC:'; then
      MAGIC=true
    fi
  fi
fi

if [ "$MAGIC" = "true" ]; then
  TRACK="/tmp/magic-docs-${SESSION_ID}.txt"

  # Atomic append with dedup
  if command -v flock >/dev/null 2>&1; then
    flock "$TRACK" bash -c \
      "grep -qxF '${FILE_PATH}' '${TRACK}' 2>/dev/null || echo '${FILE_PATH}' >> '${TRACK}'"
  else
    grep -qxF "$FILE_PATH" "$TRACK" 2>/dev/null || echo "$FILE_PATH" >> "$TRACK"
  fi
fi

exit 0
