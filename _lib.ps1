# 共用工具：memory.md 的解析与写入（供 hooks 与 mem 命令使用）
$script:MbDir  = $PSScriptRoot
$script:MbFile = Join-Path $script:MbDir 'memory.md'

function Get-MbStamp { (Get-Date).ToString('yyyy-MM-dd HH:mm') }

function Get-MbText {
  if (-not (Test-Path $script:MbFile)) { return '' }
  return (Get-Content -Raw -Encoding UTF8 $script:MbFile)
}

function Get-MbSection([string]$name) {
  $txt = Get-MbText
  if (-not $txt) { return '' }
  $m = [regex]::Match($txt, '(?ms)^##\s+' + [regex]::Escape($name) + '\s*$(.*?)(?=^##\s|\z)')
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value.Trim()
}

function Add-MbEntry([string]$name, [string]$text) {
  $text = $text.Trim()
  if (-not $text) { return $null }
  $txt = Get-MbText
  if (-not $txt) { $txt = "# Memory Bridge`n" }
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($l in ($txt -split "`r?`n")) { $lines.Add($l) }

  $head = '- [' + (Get-MbStamp) + '] ' + (((($text -split "`r?`n")[0])).Trim())
  $entry = [System.Collections.Generic.List[string]]::new()
  $entry.Add($head)
  $rest = ($text -split "`r?`n")
  for ($i = 1; $i -lt $rest.Count; $i++) {
    if ($rest[$i].Trim()) { $entry.Add('  ' + $rest[$i].Trim()) }
  }
  $entry.Add('')

  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ('^##\s+' + [regex]::Escape($name) + '\s*$')) { $idx = $i; break }
  }

  if ($idx -lt 0) {
    $lines.Add('')
    $lines.Add('## ' + $name)
    foreach ($e in $entry) { $lines.Add($e) }
  } else {
    $at = $idx + 1
    while ($at -lt $lines.Count -and $lines[$at].Trim() -eq '') { $at++ }
    $lines.InsertRange($at, $entry)
  }

  $out = ($lines -join "`n") + "`n"
  $tmp = $script:MbFile + '.tmp'
  Set-Content -Path $tmp -Value $out -Encoding utf8NoBOM -NoNewline
  Move-Item -Force $tmp $script:MbFile
  return $head
}
