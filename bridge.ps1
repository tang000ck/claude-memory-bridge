# bridge —— memory-bridge 服务与 Funnel 的日常开关
#   bridge start      启动 MCP server（127.0.0.1:8787）
#   bridge stop       停掉
#   bridge status     健康检查 + funnel 状态
#   bridge on         开 Funnel，打印 claude.ai 该填的 connector URL
#   bridge off        关 Funnel（等于切断公网入口）
#   bridge url        只打印 URL
param([Parameter(Position = 0)][string]$cmd = 'status')
$mb = $PSScriptRoot
$node = 'C:\Program Files\nodejs\node.exe'
$log = Join-Path $mb 'server.log'
$err = Join-Path $mb 'server.err.log'
$tokPath = Join-Path $mb 'token.txt'
$tok = if (Test-Path $tokPath) { (Get-Content -Raw $tokPath).Trim() } else { '' }
# tailscale 装在 D:\Apps\Tailscale（不在 C 盘），当前会话 PATH 可能还没刷新
$tsExe = if (Get-Command tailscale -ErrorAction SilentlyContinue) { (Get-Command tailscale).Source }
         elseif (Test-Path 'D:\Apps\Tailscale\tailscale.exe') { 'D:\Apps\Tailscale\tailscale.exe' }
         else { 'tailscale' }

function Get-PortPid {
  (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
}

function Get-FunnelUrl {
  try {
    $n = (& $tsExe status --json 2>$null | ConvertFrom-Json).Self.DNSName
    if (-not $n) { return $null }
    return "https://$($n.TrimEnd('.'))/mcp?token=$tok"
  } catch { return $null }
}

switch ($cmd.ToLower()) {
  'start' {
    if (Get-PortPid) { Write-Host '已在运行 (pid ' + (Get-PortPid) + ')'; break }
    $env:MB_TOKEN = $tok
    $env:MB_ALLOW_QUERY = '0'   # 只认 header / Bearer，URL 里不能带 token
    $p = Start-Process -FilePath $node -ArgumentList "`"$mb\server.mjs`"" -WindowStyle Hidden `
      -RedirectStandardOutput $log -RedirectStandardError $err -PassThru
    Start-Sleep -Seconds 2
    if ($p.HasExited) { Write-Host '启动失败，看 server.err.log'; Get-Content $err -Tail 20 } else { Write-Host "已启动 pid $($p.Id)" }
  }
  'stop' {
    $pid0 = Get-PortPid
    if ($pid0) { Stop-Process -Id $pid0 -Force; Write-Host "已停止 pid $pid0" } else { Write-Host '没在运行' }
  }
  'status' {
    $alive = $false
    try { $alive = (Invoke-WebRequest "http://127.0.0.1:8787/health?token=$tok" -TimeoutSec 4).Content -like 'ok*' } catch { }
    $state = if ($alive) { 'up' } else { 'down' }
    Write-Host "server: $state"
    try { Write-Host 'funnel:'; & $tsExe funnel status 2>&1 | Select-Object -First 10 } catch { Write-Host 'funnel: tailscale 未装或未登录' }
  }
  'on' {
    if (-not (Get-PortPid)) { Write-Host '先 bridge start'; break }
    & $tsExe funnel --bg 8787 2>&1 | Select-Object -First 12
    $u = Get-FunnelUrl
    Write-Host ''
    Write-Host 'connector URL：' -ForegroundColor Cyan
    Write-Host $u
  }
  'off' { & $tsExe funnel off 2>&1 | Select-Object -First 6; Write-Host '公网入口已关闭' }
  'url' { Write-Host (Get-FunnelUrl) }
  default { Write-Host 'bridge start|stop|status|on|off|url' }
}
