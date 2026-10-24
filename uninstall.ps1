# uninstall.ps1 — 卸载 claude-memory-bridge
$ErrorActionPreference = 'Continue'
$dest = Join-Path $env:USERPROFILE '.claude\memory-bridge'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

Write-Host '==> 关闭公网入口与服务'
try { & (Join-Path $dest 'bridge.ps1') off } catch { }

$port = (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
if ($port) { Stop-Process -Id $port -Force; Write-Host "    停止 server pid $port" }

Write-Host '==> 删除计划任务'
Unregister-ScheduledTask -TaskName 'MemoryBridge' -Confirm:$false -ErrorAction SilentlyContinue

Write-Host '==> 从 settings.json 移除 hooks'
if (Test-Path $settings) {
  $backup = Get-ChildItem "$settings.bak-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($backup) {
    Copy-Item $backup.FullName $settings -Force
    Write-Host "    已用备份恢复: $($backup.Name)"
  } else {
    $json = Get-Content -Raw -Encoding UTF8 $settings | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains 'hooks') {
      $json.PSObject.Properties.Remove('hooks')
      $json | ConvertTo-Json -Depth 12 | Set-Content $settings -Encoding utf8NoBOM
      Write-Host '    已移除 hooks 键'
    }
  }
}

Write-Host '==> 删除运行目录'
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest; Write-Host "    已删除 $dest" }
Write-Host '完成。Tailscale 如需卸载: winget uninstall Tailscale.Tailscale'
