---
name: update-docs
description: Manually update all Magic Doc files in the project with learnings from this conversation
allowedTools:
  - Read
  - Edit
  - Grep
  - Glob
---

Search the current project for all markdown files containing a `# MAGIC DOC:` header.

Use Grep to find them:
```
grep -r "^# MAGIC DOC:" --include="*.md" -l
```

For each file found:
1. Read the file to get its current contents
2. Check for an italicized line immediately after the `# MAGIC DOC: [title]` header — if present, treat it as custom instructions for how this document should be updated
3. Review the conversation history for any substantial new information relevant to this document's topic
4. If there is new information worth preserving, use the Edit tool to update the document

Update rules:
- **Preserve the header** — never modify `# MAGIC DOC: [title]` or the instructions line
- **Update in-place** — this is living documentation, not a changelog. Replace outdated info rather than appending "Updated on..." notes
- **Be terse** — high signal only, no filler words or unnecessary elaboration
- **Document WHY, not WHAT** — focus on architecture, patterns, entry points, design decisions, and non-obvious gotchas
- **Skip the obvious** — do not document things that are clear from reading the source code
- **Clean up** — remove or replace sections that are no longer relevant
- **Fix errors** — correct typos, broken formatting, or outdated information you notice

If there is nothing substantial to add for a file, skip it entirely and say so.
