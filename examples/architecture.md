# MAGIC DOC: Project Architecture
*Focus on high-level design decisions, component relationships, and non-obvious patterns*

## Overview

Magic Docs replicates Anthropic's internal-only self-updating documentation feature using Claude Code's public hook system. Two shell scripts coordinate via a session-scoped temp file to detect magic doc reads and trigger updates at turn boundaries.

## Components

- **`scripts/magic-docs-detect.sh`** — PostToolUse hook. Single-pass `jq` filter checks `tool_response.type == "text"` then tests first 200 chars for `^# MAGIC DOC:` regex. Appends file path to `/tmp/magic-docs-{session_id}.txt` with `flock` for atomicity.
- **`scripts/magic-docs-stop.sh`** — Stop hook. Reads tracking file, emits update instructions to stderr, exits with code 2 to re-wake the model. Guards against infinite loops via `stop_hook_active` flag.
- **`skills/update-docs.md`** — Manual `/update-docs` skill. Greps project for magic doc headers and updates them on demand.
- **`install.sh`** — Copies scripts/skills into `~/.claude/`, merges hook config into `settings.json` via `jq`.

## Design Decisions

- **Exit code 2 for model re-wake**: Claude Code treats exit code 2 from hooks as a "blocking error" — stderr is injected as a `Stop hook feedback:` user message and the model re-enters the query loop with `stopHookActive: true`. This is the only public mechanism to re-wake the model from a Stop hook.
- **Temp file tracking over in-memory state**: Hooks run as separate shell processes with no shared memory. A session-scoped temp file (`/tmp/magic-docs-{session_id}.txt`) bridges the PostToolUse and Stop hooks.
- **`flock` for atomicity**: Multiple concurrent Read calls can fire PostToolUse hooks in parallel. `flock` prevents duplicate entries and write corruption. Falls back to unlocked append on macOS.
- **Prompt-guided tool restriction**: The internal version enforces Edit-only access via `canUseTool`. The public version relies on the stderr prompt instructions since hooks can't restrict tool access.

## Entry Points

- Start with `install.sh` to understand the deployment model
- `scripts/magic-docs-detect.sh` is the simplest script (~25 lines) — read it first
- `scripts/magic-docs-stop.sh` shows the exit-code-2 trick that makes everything work
