#!/usr/bin/env bash
# magic-docs-stop.sh — Stop hook for Claude Code
#
# Fires when the model produces a final response (no more tool calls).
# Checks if any Magic Doc files were read during this conversation.
# If so, exits with code 2 to re-wake the model with update instructions
# injected via stderr.
#
# The model then reads and edits the tracked files with full conversation
# context. On the next stop, stop_hook_active=true prevents an infinite loop.

set -euo pipefail

# Read the full hook input (JSON on stdin)
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Guard: if stop_hook_active is true, the model was already re-woken by us.
# Exit cleanly to break the loop.
[ "$STOP_ACTIVE" = "true" ] && exit 0

# No session ID means something is wrong — exit silently
[ -n "$SESSION_ID" ] || exit 0

TRACK="/tmp/magic-docs-${SESSION_ID}.txt"

# No tracking file or empty — nothing to update
[ -s "$TRACK" ] || exit 0

# Read tracked file paths and clean up the tracking file
FILES=$(cat "$TRACK")
rm -f "$TRACK"

# Write update instructions to stderr.
# Exit code 2 tells Claude Code this is a "blocking error" — the stderr
# content gets injected as: "Stop hook feedback:\n[command]: {stderr}"
# and the model re-wakes to act on it.
cat >&2 <<EOF
Magic Doc files were read during this conversation and should be updated with new learnings.

For each file listed below:
1. Read the file to get its current contents
2. Verify it still has the # MAGIC DOC: header — skip if the header was removed
3. If there is an italicized line immediately after the header, treat it as custom update instructions
4. Use the Edit tool to update the document with substantial new information from this conversation
5. Preserve the # MAGIC DOC: header and any instruction line exactly as-is
6. Update content in-place — this is living documentation, not a changelog
7. Be terse. High signal only. Focus on architecture, patterns, design decisions, and non-obvious gotchas
8. Do NOT document things that are obvious from reading the source code
9. If there is nothing substantial to add for a file, skip it entirely

Files to update:
${FILES}
EOF

exit 2
