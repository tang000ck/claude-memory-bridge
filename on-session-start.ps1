# Claude Code SessionStart hook：把 claude.ai 侧的记忆注入本次会话上下文
# 只注入 shared-facts + from-claude；from-code 是自己写的，注入回去纯浪费 token
# 注意：必须强制 stdout 走 UTF-8，否则中文会被 Claude Code 当成乱码
. "$PSScriptRoot\_lib.ps1"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

$facts  = Get-MbSection 'shared-facts'
$claude = Get-MbSection 'from-claude'
if (-not $facts -and -not $claude) { exit 0 }

# 记录一次调用，用于验证 hook 是否真的被 Claude Code 触发
try {
  Add-Content -Path (Join-Path $PSScriptRoot 'hook.log') -Encoding utf8NoBOM `
    -Value ("{0} SessionStart injected {1} chars" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), ($facts.Length + $claude.Length))
} catch { }

$out = [System.Collections.Generic.List[string]]::new()
$out.Add('<memory-bridge 来源="与 claude.ai 共用的本机记忆文件" 刷新="' + (Get-MbStamp) + '">')
if ($facts)  { $out.Add('## shared-facts');  $out.Add($facts) }
if ($claude) { $out.Add('## from-claude');    $out.Add($claude) }
$out.Add('</memory-bridge>')

$s = ($out -join "`n")
if ($s.Length -gt 3500) { $s = $s.Substring(0, 3500) + "`n...(已截断)" }

# 直接写 UTF-8 字节到 stdout，绕开控制台代码页
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($s + "`n")
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
