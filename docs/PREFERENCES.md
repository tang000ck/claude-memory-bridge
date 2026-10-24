# The preference layer

Two of the three write paths are driven by the model's own judgement rather than a hook.
That judgement comes from **standing instructions on each side** — this file is the text to paste.

| Side | Where it lives | Applies to |
|---|---|---|
| claude.ai | Settings → Profile → **Personal preferences** (+ per-Project custom instructions if you work in Projects) | every conversation |
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` (global) or `<project>\CLAUDE.md` | every session |

Hooks still matter: models are unreliable about "the session is ending", so the `Stop` hook
keeps a zero-token record of changed files as a floor. Preferences make the record *meaningful*;
the hook makes sure something is written at all.

## What to ask for

Two failure modes to avoid:

- **Too eager** — a line per turn, and the file becomes a transcript nobody reads. It is injected
  into every Claude Code session, so bloat is paid for in tokens at each start.
- **Too shy** — "only when the user says remember", and nothing is ever written.

The rules below aim at "one entry per finished piece of work, with the conclusions that would be
expensive to rediscover".

## claude.ai — personal preferences

```
I have two sets of memory tools — keep them apart:
- memory_read / memory_write etc.: claude.ai's own memory, unrelated to my computer.
- read_memory / append_memory / search_memory (connector "memory"): my local memory.md, shared across surfaces.

Rules:
1. Write automatically only when a piece of work is finished and the conclusion is settled
   (a decision, a preference, an analysis result). One entry per project.
2. Content: project name + what was done + key conclusion/decision + artifact path or open items.
   Skip process, code, and dialogue recap. Two or three sentences; prefer one extra sentence
   over losing something important.
3. Small questions, Q&A, one-off lookups, mid-task progress: do not write.
4. "Write it to the bridge" from me means write unconditionally.
5. Never write passwords, tokens, or keys.
6. When I ask what I have been doing in the terminal or code, call read_memory(section=from-code)
   first instead of guessing.
```

## Claude Code — `~/.claude/CLAUDE.md`

```markdown
## Memory bridge (claude.ai ↔ Claude Code)

There is one memory file shared with claude.ai:
`C:\Users\<you>\.claude\memory-bridge\memory.md`
Sections: `## shared-facts` (both read), `## from-claude` (written there), `## from-code` (written here).
Format: `- [YYYY-MM-DD HH:MM] content`, newest entry directly under the section header.

### When to write
- Only when a substantial piece of work finishes (multi-step, multi-file, long-running), at the
  point the conclusion is settled, before the final reply: insert one line under `## from-code`
  as `- [YYYY-MM-DD HH:MM] project: what was done + key conclusion/decision + artifact path or open items`
- Small tasks (one-line fix, Q&A, single lookup, mid-task progress) are not written.
- The user saying "收工 / 先这样 / 记一下" means write a summary now.
- "写到桥里" means write unconditionally.

### How
- Keep what is needed to resume in another session (conclusions, decisions, artifact paths, open
  items); drop process, code, and transcript recap.
- One entry per project, at most 3 per session, never one per turn.
- Read `## from-code` before inserting to avoid duplicates.
- Never write passwords, tokens, keys, or ID numbers.

### When to read
- About to state "I decided X earlier" or "the conclusion was Y": read `## shared-facts` and
  `## from-claude` first.
- Do not read the whole file at every session start; only when relevant.
```

## Tuning

| Symptom | Fix |
|---|---|
| File grows past ~5 KB | tighten "one entry per project"; archive old entries to `archive.md` |
| Nothing is ever written | hook coverage is doing the work; check `hook.log`, then make rule 1 more explicit |
| Duplicate entries | add "read the section before inserting" to both sides |
| Entries read like a diary | change rule 2 to name the artifact path and the open items only |
