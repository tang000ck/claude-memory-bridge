# claude-memory-bridge

Share one memory between **claude.ai** (web/app) and **Claude Code** (terminal/desktop) — bidirectional, on demand, and with **zero model calls** in the sync path.

claude.ai keeps its memory server-side; Claude Code keeps its memory on disk. There is no API between them. This project bridges them with a single markdown file plus a tiny MCP server that claude.ai reaches over HTTPS.

```
claude.ai / Claude App ──HTTPS (Tailscale Funnel)──┐
                                                   ├── memory.md  (one file, on your disk)
Claude Code ──SessionStart / Stop hooks────────────┘
```

## Why not periodic summarization

Most "memory sync" tools call a model on a schedule to summarize and re-upload. That burns quota on every sync and drifts from the source. Here the source of truth **is** the file:

| Direction | Mechanism | Model calls |
|---|---|---|
| claude.ai → file | MCP tool `append_memory` (it writes when something durable happens) | 0 |
| file → Claude Code | `SessionStart` hook injects `shared-facts` + `from-claude` (~800 tokens, cacheable) | 0 |
| Claude Code → file | `Stop` hook records `git status`, or recently modified files, throttled | 0 |
| file → claude.ai | MCP tool `read_memory` / `search_memory`, read on demand | 0 |

Nothing is duplicated into claude.ai's own memory panel (that surface has no write API), and the bridge content is **not** held in claude.ai's standing context — it is fetched only when relevant.

## Requirements

- Windows with PowerShell 7 (`pwsh`), Node.js 18+
- A Tailscale account (free tier is fine) with Funnel enabled
- claude.ai Pro/Max/Team/Enterprise for custom connectors
- Claude Code

## Install

```powershell
git clone https://github.com/<you>/claude-memory-bridge.git D:\Projects\claude-memory-bridge
cd D:\Projects\claude-memory-bridge
pwsh -NoProfile -File .\install.ps1
```

`install.ps1` copies the runtime into `%USERPROFILE%\.claude\memory-bridge`, generates a 32-byte token, backs up `~/.claude/settings.json`, adds the two hooks, and registers a logon scheduled task so the server comes back after reboot.

Then:

```powershell
$mb = "$env:USERPROFILE\.claude\memory-bridge"
& "$mb\bridge.ps1" start     # MCP server on 127.0.0.1:8787
& "$mb\bridge.ps1" on        # Tailscale Funnel, prints the public URL
& "$mb\bridge.ps1" status
& "$mb\bridge.ps1" off       # close the public entry point
```

## Connect claude.ai

1. `bridge.ps1 on` → note the printed URL, e.g. `https://your-host.tailXXXX.ts.net/mcp`
2. claude.ai → Settings → Connectors → **Add custom connector**
3. Name `memory`, URL as above (**no token in the URL**)
4. Authentication: **No sign-in**
5. Request headers → **Add header**: name `Authorization`, value `Bearer <token from token.txt>`
6. Save

Header whitelist gotcha: claude.ai rejects custom header names such as `x-mb-token`. Use the standard `Authorization: Bearer …` form.

Verify by asking Claude to call `read_memory` with `section=from-code`.

## Layout

| File | Purpose |
|---|---|
| `memory.md` | the shared memory (three sections, newest entries on top) |
| `server.mjs` | dependency-free MCP server (Streamable HTTP + JSON), header-token auth, 120 req/min |
| `bridge.ps1` | start/stop/status/on/off/url for the server and Funnel |
| `mem.ps1` / `mem.cmd` | manual entry: copy whole file, `pull` from clipboard, `add`, `log` |
| `on-session-start.ps1` | SessionStart hook: injects `shared-facts` + `from-claude` as UTF-8 |
| `on-stop.ps1` | Stop hook: records git changes, else recently modified files (whitelisted extensions) |
| `config.json` | optional: `{ "scanDirs": ["%USERPROFILE%\\Desktop\\myproject"] }` |

## Security

- Server listens on `127.0.0.1` only; the public entry point is Tailscale Funnel
- Token via `Authorization: Bearer`; `?token=` is rejected (`MB_ALLOW_QUERY=0`), so the URL is not a secret
- Only three tools, no filesystem path arguments, paths are fixed server-side
- Turn it off when you do not need it: `bridge.ps1 off`
- The memory file is injected into Claude Code's context, so treat anything written into it as model input — review it occasionally

## Known limits

- claude.ai's native memory panel cannot be written to; it will not mirror this file
- Machine must be awake and online for claude.ai to reach it
- Keep `memory.md` small (under ~5 KB): it is injected at every Claude Code session start
- Tailscale Funnel is for personal use, subject to its own terms

## Uninstall

```powershell
pwsh -NoProfile -File .\uninstall.ps1
```

Restores `settings.json` from the backup, removes the scheduled task, stops the server, and deletes the runtime directory.

## License

MIT
