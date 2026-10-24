# Connecting claude.ai

The claude.ai side is a **custom connector** pointing at your machine through Tailscale Funnel.

## 1. Expose the MCP server

```powershell
$mb = "$env:USERPROFILE\.claude\memory-bridge"
& "$mb\bridge.ps1" start    # 127.0.0.1:8787
& "$mb\bridge.ps1" on       # Tailscale Funnel -> https://<host>.<tailnet>.ts.net
```

First run needs Funnel enabled for your tailnet. `tailscale funnel` prints an admin link
(`https://login.tailscale.com/f/funnel?node=...`); open it and click **Enable Funnel**.

## 2. Add the connector

claude.ai → **Settings → Connectors → Add custom connector**

| Field | Value |
|---|---|
| Name | `memory` |
| URL | `https://<host>.<tailnet>.ts.net/mcp` — **no token in the URL** |
| Authentication | `No sign-in` |
| Request headers → Add header | `Authorization` = `Bearer <token from token.txt>` |
| Transport (Advanced) | `Streamable HTTP` (default) |

## 3. Verify

Ask Claude: *"call read_memory with section=from-code and quote the first line"*.
Every request is appended to `access.log` next to `memory.md`, so you can confirm server-side.

## Troubleshooting

**"The header name … isn't approved."**
claude.ai only accepts an allowlist of header names. Custom names such as `x-mb-token` are
rejected. Use the standard `Authorization: Bearer <token>` form — the server accepts both.

**Connector detected OAuth / "Sign in now".**
The server answers `401` when the token is missing, and the UI guesses OAuth. Choose
**No sign-in** and set the header manually.

**401 on every request.**
`MB_ALLOW_QUERY=0` is set by `bridge.ps1`, which disables `?token=` URLs. Send the token in
the header only. If the token is lost, delete `token.txt` and restart the server; a new one
is generated.

**Tool call works but memory looks unavailable.**
The machine must be awake and online; `bridge.ps1 status` shows server and Funnel state.

## Suggested personal preference

Paste into claude.ai → Settings → Profile → Personal preferences:

```
I have two sets of memory tools — keep them apart:
- memory_read / memory_write etc.: claude.ai's own memory, unrelated to my computer.
- read_memory / append_memory / search_memory (connector "memory"): my local memory.md, shared across surfaces.

Rules:
1. When I ask what I have been doing in the terminal or code, call read_memory (section=from-code) first instead of guessing.
2. When a durable conclusion, decision, preference or project fact emerges, call append_memory (section=from-claude) — one sentence, conclusion only, at most 2-3 entries per conversation.
3. Never write small talk, one-off lookups, or temporary information.
4. Never write passwords, tokens or keys.
```
