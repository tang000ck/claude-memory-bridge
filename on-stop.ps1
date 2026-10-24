# Claude Code Stop hook：把本次工作时改动的文件清单记进 from-code（不调模型，0 token）
# 两条路：① 当前目录是 git 仓库且有改动 -> 记 git status；② 否则扫指定目录里最近改过的文件
# 节流：30 分钟内最多写一次；没有任何改动就不写
. "$PSScriptRoot\_lib.ps1"

# 扫描范围（只扫这些目录里最近改动过的文件）
$ScanDirs = @()
$cfgPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $cfgPath) {
  try {
    $cfg = Get-Content -Raw -Encoding UTF8 $cfgPath | ConvertFrom-Json
    if ($cfg.scanDirs) {
      $ScanDirs = @($cfg.scanDirs | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
    }
  } catch { }
}
$Exclude = 'node_modules|\\\.git\\|\\dist\\|\\build\\|\\\.next\\|__pycache__|\\\.venv\\|\\\.cache\\|\\target\\'
$ScanMinutes = 60   # 往回看多久以内的改动
$MaxFiles = 10
# 只记这些扩展名，避免 parquet/csv 之类的数据文件把记录冲成噪音
$IncludeExt = @('.py', '.js', '.mjs', '.ts', '.tsx', '.jsx', '.md', '.txt', '.html', '.css', '.json',
  '.ps1', '.cmd', '.sh', '.yml', '.yaml', '.toml', '.ini', '.sql', '.vue', '.svelte', '.ipynb')

$marker = Join-Path $PSScriptRoot '.last-code-log'
if (Test-Path $marker) {
  $age = ((Get-Date) - (Get-Item $marker).LastWriteTime).TotalMinutes
  if ($age -lt 30) { exit 0 }
}

# 读 hook 传入的 JSON（可能为空）
$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { }
$cwd = $null
if ($raw) {
  try { $j = $raw | ConvertFrom-Json; if ($j.cwd) { $cwd = $j.cwd } } catch { }
}
if (-not $cwd -or -not (Test-Path $cwd)) { $cwd = (Get-Location).Path }

# ① git 路线
$line = $null
Push-Location $cwd
try { $st = git status --short 2>$null } catch { $st = $null }
Pop-Location

if ($st) {
  $files = @($st | ForEach-Object { ($_ -replace '^\s*\S+\s+', '').Trim() } | Where-Object { $_ })
  if ($files.Count -gt 0) {
    $repoName = Split-Path $cwd -Leaf
    $shown = ($files | Select-Object -First $MaxFiles) -join '、'
    if ($files.Count -gt $MaxFiles) { $shown += " 等 $($files.Count) 个" }
    $line = "代码侧（$repoName）：git 改动 $($files.Count) 个文件 — $shown"
  }
}

# ② 文件时间路线
if (-not $line) {
  $since = (Get-Date).AddMinutes(-$ScanMinutes)
  $recent = @()
  foreach ($d in $ScanDirs) {
    if (-not (Test-Path $d)) { continue }
    $recent += Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue |
      Where-Object {
        $_.LastWriteTime -gt $since -and
        $_.FullName -notmatch $Exclude -and
        $_.Name -notlike '.*' -and
        $IncludeExt -contains $_.Extension.ToLower()
      }
  }
  if ($recent.Count -gt 0) {
    $recent = $recent | Sort-Object LastWriteTime -Descending
    $names = ($recent | Select-Object -First $MaxFiles | ForEach-Object {
        "{0}（{1:HH:mm}）" -f (Split-Path $_.FullName -Leaf), $_.LastWriteTime
      }) -join '、'
    $dirName = ($ScanDirs | ForEach-Object { Split-Path $_ -Leaf }) -join '/'
    $line = "代码侧（$dirName）：最近 $ScanMinutes 分钟内改过 $($recent.Count) 个文件 — $names"
  }
}

if (-not $line) { exit 0 }

Add-MbEntry 'from-code' $line | Out-Null
Set-Content -Path $marker -Value (Get-MbStamp) -Encoding utf8NoBOM
exit 0
