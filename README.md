# Magic Docs — Self-Updating Documentation for Claude Code

**Magic Docs** automatically keeps your markdown documentation files up-to-date by leveraging Claude Code's hook system. Mark any markdown file with a `# MAGIC DOC:` header, and it will be updated with new learnings whenever Claude reads it during a conversation.

---

## Origin Story

On **March 31, 2026**, the full source code of Anthropic's Claude Code CLI [was leaked](https://x.com/Fried_rice/status/2038894956459290963) via a `.map` file exposed in their npm registry. Among the ~1,900 files and 380K+ lines of TypeScript was an **internal-only feature called Magic Docs** (`src/services/MagicDocs/`).

The internal version uses two private APIs not exposed to users:
- `registerFileReadListener()` — detects when files with magic headers are read
- `registerPostSamplingHook()` — runs a background Sonnet subagent after each model turn

The source code comment even notes: *"Post-sampling hook — not exposed in settings.json config (yet)"*.

This project **replicates the Magic Docs feature using only public Claude Code hooks**, making it available to everyone today.

---

## How It Works

```
You read a file with "# MAGIC DOC: My Title" header
         │
         ▼
PostToolUse hook fires on the Read tool
         │
         ▼
Detection script checks for the header,
writes the file path to a tracking file
         │
         ▼
  ... conversation continues ...
         │
         ▼
Model stops (no more tool calls)
         │
         ▼
Stop hook fires, finds tracked files
         │
         ▼
Script exits with code 2 (blocking error)
stderr = update instructions
         │
         ▼
Model re-wakes with "Stop hook feedback: ..."
         │
         ▼
Model reads each magic doc and edits it
with new learnings from the conversation
         │
         ▼
Model stops again — Stop hook sees
stop_hook_active=true → exits 0 (no loop)
```

### The Key Trick: Exit Code 2

Claude Code's hook system treats **exit code 2** as a "blocking error". The script's stderr is injected into the conversation as a user message (`Stop hook feedback:\n...`), and the model **re-wakes** to act on it. The `stop_hook_active` flag in the next Stop hook invocation prevents an infinite loop.

This mechanism was discovered by reading the leaked source at `src/query.ts:1282-1305` and `src/utils/hooks.ts:2647-2668`.

---

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `jq` — JSON processor (`sudo pacman -S jq` / `sudo apt install jq` / `brew install jq`)
- `flock` — file locking (standard on Linux; optional on macOS)

### Quick Install

```bash
git clone https://github.com/yfe404/magic-docs.git
cd magic-docs
./install.sh
```

This will:
1. Copy hook scripts to `~/.claude/scripts/`
2. Copy the `/update-docs` skill to `~/.claude/skills/`
3. Merge hook configuration into `~/.claude/settings.json`

### Manual Install

1. Copy scripts:
   ```bash
   mkdir -p ~/.claude/scripts
   cp scripts/magic-docs-detect.sh ~/.claude/scripts/
   cp scripts/magic-docs-stop.sh ~/.claude/scripts/
   chmod +x ~/.claude/scripts/magic-docs-*.sh
   ```

2. Copy skill:
   ```bash
   mkdir -p ~/.claude/skills
   cp skills/update-docs.md ~/.claude/skills/
   ```

3. Add hooks to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Read",
           "hooks": [
             {
               "type": "command",
               "command": "~/.claude/scripts/magic-docs-detect.sh",
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
               "command": "~/.claude/scripts/magic-docs-stop.sh",
               "timeout": 10
             }
           ]
         }
       ]
     }
   }
   ```

---

## Usage

### Creating a Magic Doc

Add `# MAGIC DOC: Your Title` as the **first line** of any markdown file:

```markdown
# MAGIC DOC: Architecture Overview
*Focus on system design patterns and key entry points*

## Overview

This project uses a microservices architecture with...
```

- The **title** tells Claude what the document is about
- The optional **italicized line** below the header provides custom instructions for how updates should be made

### Automatic Updates

Once installed, Magic Docs works automatically:

1. During a Claude Code conversation, read a file that has the `# MAGIC DOC:` header
2. Continue your conversation — discuss architecture, debug issues, explore the codebase
3. When Claude finishes responding, the Stop hook triggers and Claude updates the magic doc with new learnings

### Manual Updates

Run the `/update-docs` skill in Claude Code at any time:

```
/update-docs
```

This scans the project for all `# MAGIC DOC:` files and updates them based on the current conversation.

---

## Examples

### Project Architecture Doc

```markdown
# MAGIC DOC: Architecture
*Track high-level design decisions and component relationships*

## Core Components

- **API Gateway** — Express.js, handles auth and rate limiting
- **Worker Service** — Bull queue consumer, processes async jobs
- **Database** — PostgreSQL with Prisma ORM

## Key Design Decisions

- Chose event sourcing for audit trail (compliance requirement)
- WebSocket for real-time updates instead of polling (latency sensitive)
```

### API Reference

```markdown
# MAGIC DOC: API Endpoints
*Document non-obvious API behaviors and integration gotchas*

## Authentication

All endpoints require Bearer token. Tokens expire after 1h.
Refresh tokens are rotated on use (one-time).

## Rate Limits

- 100 req/min per user (429 response)
- Bulk endpoints: 10 req/min
```

### Onboarding Guide

```markdown
# MAGIC DOC: Getting Started
*Keep this beginner-friendly — focus on what's surprising or non-obvious*

## First-Time Setup

Run `make dev` — this starts Docker, seeds the DB, and watches for changes.
Note: first run takes ~5min because it builds the Rust FFI bindings.

## Common Pitfalls

- Don't run migrations manually — `make dev` handles it
- Tests require `TEST_DB_URL` env var (see .env.example)
```

---

## How It Differs from the Internal Version

| Aspect | Anthropic Internal | This Implementation |
|--------|-------------------|---------------------|
| Detection | In-process callback (zero overhead) | PostToolUse shell hook (~50ms per Read) |
| Trigger | After every model turn when idle | Only when model naturally stops |
| Executor | Silent background Sonnet subagent | Main model re-waked via exit code 2 |
| Visibility | Completely invisible to user | Visible — model announces what it's updating |
| Tool restriction | Only Edit tool, only the specific file | No enforcement (prompt-guided) |
| Loop prevention | `querySource` check + `sequential()` | `stop_hook_active` flag |
| Custom prompt | `~/.claude/magic-docs/prompt.md` | Edit the Stop hook stderr message |

---

## Uninstall

```bash
rm ~/.claude/scripts/magic-docs-detect.sh
rm ~/.claude/scripts/magic-docs-stop.sh
rm ~/.claude/skills/update-docs.md
# Remove the hooks entries from ~/.claude/settings.json
```

Clean up any leftover tracking files:
```bash
rm -f /tmp/magic-docs-*.txt
```

---

## How the Internal Version Works

For the curious, here's what Anthropic built internally (from the leaked source):

1. **`registerFileReadListener()`** — A callback registered on the FileReadTool. Every time any file is read, it checks the first line for `# MAGIC DOC:` and registers the file for tracking.

2. **`registerPostSamplingHook()`** — A hook that fires after every model response. When the conversation is idle (no tool calls in the last turn), it iterates over all tracked magic docs.

3. **For each tracked doc**, a **Sonnet subagent** is forked via `runAgent()` with:
   - The full conversation history (shared prompt cache)
   - Only the `FileEdit` tool allowed
   - A custom `canUseTool` function that restricts edits to only that specific file
   - A detailed prompt template (in `src/services/MagicDocs/prompts.ts`)

4. Updates are wrapped in `sequential()` to prevent concurrent writes.

5. The feature is gated behind `process.env.USER_TYPE === 'ant'` — it only runs for Anthropic employees.

**Key files in the leaked source:**
- `src/services/MagicDocs/magicDocs.ts` — Core implementation (~255 lines)
- `src/services/MagicDocs/prompts.ts` — Update prompt template (~128 lines)

---

## License

MIT
