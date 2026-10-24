**中文** · [English](README.md)

# claude-memory-bridge

让 **claude.ai**（网页 / App）和 **Claude Code**（终端 / 桌面端）共用一份记忆——双向、按需、且**同步路径上 0 次模型调用**。

claude.ai 的记忆存在 Anthropic 服务端，Claude Code 的记忆存在本地磁盘，两者之间没有 API。这个项目用一个 markdown 文件、加上一个极小的 MCP server 把它们接起来：claude.ai 通过 HTTPS 访问这台机器上的文件。

```
claude.ai / Claude App ──HTTPS（Tailscale Funnel）──┐
                                                    ├── memory.md（唯一真源，在你磁盘上）
Claude Code ──SessionStart / Stop hooks─────────────┘
```

## 为什么不用「定时摘要」

多数记忆同步工具会定时调一次模型，把记忆总结后重新上传一次。那样每次同步都在烧额度，而且内容会越漂越远。这里的真源**就是那个文件**：

| 方向 | 机制 | 模型调用 |
|---|---|---|
| claude.ai → 文件 | MCP 工具 `append_memory`（出现长期有效的内容时它写） | 0 |
| 文件 → Claude Code | `SessionStart` hook 注入 `shared-facts` + `from-claude`（约 800 token，可命中缓存） | 0 |
| Claude Code → 文件 | `Stop` hook 记录 `git status` 或最近改动的文件，带节流 | 0 |
| 文件 → claude.ai | MCP 工具 `read_memory` / `search_memory`，按需现读 | 0 |

内容不会被复制进 claude.ai 的原生记忆面板（那个界面没有写接口），桥里的内容也**不会**常驻在 claude.ai 的上下文里——只有相关时才去取。

## 三个写入者

文件由三层共同写入，这是刻意设计的：

| 层 | 触发 | 成本 | 质量 |
|---|---|---|---|
| 两边的**偏好指令**（claude.ai personal preferences + `~/.claude/CLAUDE.md`） | 模型判断某项工作已收尾 | 每完成一个任务几百输出 token | 有意义：结论、决定、产物路径 |
| `Stop` hook | 每轮回复，30 分钟节流 | **0** | 兜底：文件名与时间 |
| `mem add` / `mem log` | 你手动 | 0 | 你写什么就是什么 |

偏好负责让记忆**有用**，hook 负责保证记忆**确实被写下**——因为模型对「会话结束」这个时点判断不可靠。两边可直接粘贴的规则文本见 [docs/PREFERENCES.md](docs/PREFERENCES.md)。

## 环境要求

- Windows + PowerShell 7（`pwsh`）+ Node.js 18 以上
- 一个 Tailscale 账号（免费版够用），并开通 Funnel
- claude.ai 的 Pro / Max / Team / Enterprise（自定义 connector 需要）
- Claude Code

## 安装

```powershell
git clone https://github.com/<you>/claude-memory-bridge.git D:\Projects\claude-memory-bridge
cd D:\Projects\claude-memory-bridge
pwsh -NoProfile -File .\install.ps1
```

`install.ps1` 会把运行文件复制到 `%USERPROFILE%\.claude\memory-bridge`，生成一个 32 字节随机 token，备份 `~/.claude/settings.json`，写入两个 hook，并注册一个登录时触发的计划任务，让 server 在重启后自动回来。

然后：

```powershell
$mb = "$env:USERPROFILE\.claude\memory-bridge"
& "$mb\bridge.ps1" start     # 启动 MCP server（127.0.0.1:8787）
& "$mb\bridge.ps1" on        # 开 Tailscale Funnel，打印公网地址
& "$mb\bridge.ps1" status
& "$mb\bridge.ps1" off       # 关掉公网入口
```

## 接入 claude.ai

1. `bridge.ps1 on`，记下打印出来的地址，形如 `https://your-host.tailXXXX.ts.net/mcp`
2. claude.ai → Settings → Connectors → **Add custom connector**
3. 名称 `memory`，URL 填上面那个（**URL 里不放 token**）
4. Authentication 选 **No sign-in**
5. Request headers → **Add header**：名字 `Authorization`，值 `Bearer <token.txt 里的串>`
6. 保存

**坑：claude.ai 对 header 名有白名单**，`x-mb-token` 这类自定义名会被拒，必须用标准的 `Authorization: Bearer …`。

验证：让 Claude 调用 `read_memory`，section 选 `from-code`，看它能否原文贴出内容。

## 文件构成

| 文件 | 作用 |
|---|---|
| `memory.md` | 共享记忆本体（三个区，最新条目在最上） |
| `server.mjs` | 零依赖 MCP server（Streamable HTTP + JSON），header token 鉴权，120 请求/分钟 |
| `bridge.ps1` | server 与 Funnel 的 start / stop / status / on / off / url |
| `mem.ps1` / `mem.cmd` | 手动入口：复制全文、`pull` 从剪贴板回写、`add`、`log` |
| `on-session-start.ps1` | SessionStart hook：以 UTF-8 注入 `shared-facts` + `from-claude` |
| `on-stop.ps1` | Stop hook：记录 git 改动，否则记录最近改动的文件（限白名单扩展名） |
| `config.json` | 可选：`{ "scanDirs": ["%USERPROFILE%\\Desktop\\myproject"] }` |

## 安全

- server 只监听 `127.0.0.1`，对外入口是 Tailscale Funnel
- token 走 `Authorization: Bearer`；`?token=` 被关闭（`MB_ALLOW_QUERY=0`），所以 URL 本身不是秘密，截图、分享都无所谓
- 只暴露三个工具，不接受任何文件路径参数，路径写死在服务端
- 不用的时候 `bridge.ps1 off`
- 记忆文件会被注入 Claude Code 的上下文，请把它当成模型输入看待，偶尔翻一眼

## 已知限制

- claude.ai 原生记忆面板无法写入，不会镜像这个文件
- 机器必须开机且联网，claude.ai 才连得上
- `memory.md` 要小（5KB 以内）：它会在每个 Claude Code 会话启动时被注入
- Tailscale Funnel 面向个人使用，受其自身条款约束

## 卸载

```powershell
pwsh -NoProfile -File .\uninstall.ps1
```

用备份恢复 `settings.json`、删除计划任务、停掉 server、删掉运行目录。

## 许可

MIT
