# Memory Bridge

> `claude.ai` 与 `Claude Code` 共用的单一记忆文件。
> 规则：新条目插在本节标题的正下方（最新在最上），格式 `- [YYYY-MM-DD HH:MM] 内容`。
> 手改这个文件是允许的，两边下次读取时看到的就是改后的内容。

## shared-facts

- [YYYY-MM-DD HH:MM] 长期事实区：称呼、语言、不变的技术栈、硬规则。两边都会读，不由脚本自动写。

## from-claude

- [YYYY-MM-DD HH:MM] 本区由 claude.ai 侧（connector 的 append_memory 或 `mem pull`）写入；Claude Code 每次会话开始时自动注入本区。

## from-code

- [YYYY-MM-DD HH:MM] 本区由 Claude Code 的 Stop hook 自动写入（git status 或最近改动文件；不调模型，0 token）；claude.ai 通过 read_memory 读取。
