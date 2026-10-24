# mem —— memory-bridge 手动入口
#   mem               把整个 memory.md 复制到剪贴板（拿去粘 claude.ai 的 Project knowledge）
#   mem pull          把剪贴板内容写进 from-claude（claude.ai 的结论搬回本地）
#   mem log "内容"     手动写一条 from-code
#   mem add "内容"     手动写一条 shared-facts
#   mem show          打印全文
#   mem open          用记事本打开
param(
  [Parameter(Position = 0)][string]$cmd = '',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$rest
)
. "$PSScriptRoot\_lib.ps1"

function Show-Help {
  @(
    'mem              复制全文到剪贴板',
    'mem pull         剪贴板 -> from-claude',
    'mem log "内容"    写 from-code',
    'mem add "内容"    写 shared-facts',
    'mem show         打印全文',
    'mem open         记事本打开'
  ) | ForEach-Object { Write-Host $_ }
}

switch ($cmd.ToLower()) {
  { $_ -in '', 'copy' } {
    $t = Get-MbText
    if (-not $t) { Write-Host 'memory.md 不存在'; exit 1 }
    Set-Clipboard -Value $t
    Write-Host ("已复制到剪贴板：{0} 字符 / {1} 行" -f $t.Length, ($t -split "`n").Count)
  }
  'pull' {
    $clip = Get-Clipboard -Raw
    if (-not $clip -or -not $clip.Trim()) { Write-Host '剪贴板是空的'; exit 1 }
    $h = Add-MbEntry 'from-claude' $clip
    Write-Host "已写入 from-claude：$h"
  }
  'log' {
    $t = ($rest -join ' ').Trim()
    if (-not $t) { Write-Host '用法: mem log "内容"'; exit 1 }
    Write-Host ("已写入 from-code：" + (Add-MbEntry 'from-code' $t))
  }
  'add' {
    $t = ($rest -join ' ').Trim()
    if (-not $t) { Write-Host '用法: mem add "内容"'; exit 1 }
    Write-Host ("已写入 shared-facts：" + (Add-MbEntry 'shared-facts' $t))
  }
  'show' { Get-MbText }
  'open' { Start-Process notepad.exe $script:MbFile }
  default { Show-Help }
}
