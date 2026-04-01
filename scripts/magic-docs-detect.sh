#!/usr/bin/env bash
# magic-docs-detect.sh — PostToolUse hook for Claude Code
#
# Fires after every Read tool call. Detects files with a "# MAGIC DOC:" header
# and tracks their paths in a session-scoped temp file for later processing
# by magic-docs-stop.sh.
#
# Performance target: <50ms (fires on every file read)

set -euo pipefail

# Single-pass jq:
#   1. Skip non-text responses (images, PDFs, notebooks)
#   2. Test the first 200 chars of file content for the MAGIC DOC header
#   3. If matched, emit session_id and file_path (tab-separated)
#   4. If no match, emit nothing (jq `empty` produces no output)
jq -r '
  if .tool_response == null then empty
  elif .tool_response.type != "text" then empty
  elif (.tool_response.file.content[0:200] | test("^#\\s*MAGIC\\s+DOC:"; "im")) then
    .session_id + "\t" + .tool_input.file_path
  else empty
  end
' | {
  IFS=$'\t' read -r SESSION_ID FILE_PATH || exit 0
  [ -n "$SESSION_ID" ] && [ -n "$FILE_PATH" ] || exit 0

  TRACK="/tmp/magic-docs-${SESSION_ID}.txt"

  # Atomic append with dedup — flock prevents races when multiple
  # concurrent Read calls fire hooks in parallel
  if command -v flock >/dev/null 2>&1; then
    flock "$TRACK" bash -c \
      "grep -qxF '${FILE_PATH}' '${TRACK}' 2>/dev/null || echo '${FILE_PATH}' >> '${TRACK}'"
  else
    # Fallback without flock (macOS without coreutils)
    grep -qxF "$FILE_PATH" "$TRACK" 2>/dev/null || echo "$FILE_PATH" >> "$TRACK"
  fi
} 2>/dev/null

exit 0
