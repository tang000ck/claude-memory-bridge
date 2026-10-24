# install.ps1 — 安装 claude-memory-bridge 到 %USERPROFILE%\.claude\memory-bridge
# 用法: pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = Join-Path $env:USERPROFILE '.claude\memory-bridge'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

Write-Host "==> 安装到 $dest"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($f in Get-ChildItem $src -File | Where-Object { $_.Extension -in '.ps1', '.mjs', '.cmd', '.md' -and $_.Name -notin 'install.ps1','uninstall.ps1','README.md' }) {
  Copy-Item $f.FullName $dest -Force
  Write-Host "    + $($f.Name)"
}

# token
$tokPath = Join-Path $dest 'token.txt'
if (-not (Test-Path $tokPath)) {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $tok = ([Convert]::ToBase64String($bytes) -replace '\+', '-' -replace '/', '_' -replace '=', '')
  Set-Content -Path $tokPath -Value $tok -Encoding utf8NoBOM
  Write-Host "    + token.txt (新生成)"
} else { $tok = (Get-Content -Raw $tokPath).Trim(); Write-Host '    = token.txt 已存在，沿用' }

# memory.md
$memPath = Join-Path $dest 'memory.md'
if (-not (Test-Path $memPath)) {
  Copy-Item (Join-Path $src 'memory.example.md') $memPath -Force
  Write-Host '    + memory.md (从模板创建)'
}

# config.json
$cfgPath = Join-Path $dest 'config.json'
if (-not (Test-Path $cfgPath)) {
  Copy-Item (Join-Path $src 'config.example.json') $cfgPath -Force
  Write-Host '    + config.json (从模板创建，记得填 scanDirs)'
}

# hooks
$backup = "$settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
if (Test-Path $settings) {
  Copy-Item $settings $backup -Force
  Write-Host "==> 已备份 settings.json -> $(Split-Path $backup -Leaf)"
  $json = Get-Content -Raw -Encoding UTF8 $settings | ConvertFrom-Json
} else {
  $json = [pscustomobject]@{}
}

$pwshPath = (Get-Command pwsh).Source
$hookStart = $pwshPath + ' -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $dest 'on-session-start.ps1') + '"'
$hookStop  = $pwshPath + ' -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $dest 'on-stop.ps1') + '"'

$hooks = [ordered]@{}
if ($json.PSObject.Properties.Name -contains 'hooks' -and $json.hooks) { $hooks = $json.hooks }
$hooks['SessionStart'] = @(@{ hooks = @(@{ type = 'command'; command = $hookStart; timeout = 15 }) })
$hooks['Stop']         = @(@{ hooks = @(@{ type = 'command'; command = $hookStop;  timeout = 20 }) })
$json | Add-Member -NotePropertyName hooks -NotePropertyValue $hooks -Force
$json | ConvertTo-Json -Depth 12 | Set-Content $settings -Encoding utf8NoBOM
Write-Host '==> hooks 已写入 settings.json'

# scheduled task
$action = New-ScheduledTaskAction -Execute $pwshPath -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}\bridge.ps1" start' -f $dest)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'MemoryBridge' -Action $action -Trigger $trigger -Settings $set `
  -Description 'claude.ai <-> Claude Code memory bridge (127.0.0.1:8787)' -Force | Out-Null
Write-Host '==> 计划任务 MemoryBridge 已注册（登录时自动启动 server）'

Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host '  1) 编辑 config.json 填 scanDirs（要监控改动的目录）'
Write-Host '  2) 安装并登录 Tailscale，开通 Funnel'
Write-Host '  3) & "' + $dest + '\bridge.ps1" start ; & "' + $dest + '\bridge.ps1" on'
Write-Host '  4) 在 claude.ai 添加 custom connector，header 用 Authorization: Bearer <token.txt>'
Write-Host ''
Write-Host ('token: ' + $tok) -ForegroundColor Yellow
