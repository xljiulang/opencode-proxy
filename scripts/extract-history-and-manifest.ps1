[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $CodexUiPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sourceRoot = [IO.Path]::GetFullPath($CodexUiPath)
$historyDir = Join-Path $repoRoot "docs\history"
New-Item -ItemType Directory -Force -Path $historyDir | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File {
  param([string] $Path, [string] $Content)
  [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$changelogPath = Join-Path $sourceRoot "docs\变更记录.md"
$lines = Get-Content -LiteralPath $changelogPath
$sections = New-Object System.Collections.Generic.List[System.Collections.Generic.List[string]]
$current = $null
foreach ($line in $lines) {
  if ($line -match "^##\s+") {
    if ($null -ne $current) {
      $sections.Add($current)
    }
    $current = New-Object System.Collections.Generic.List[string]
  }
  if ($null -ne $current) {
    $current.Add($line)
  }
}
if ($null -ne $current) {
  $sections.Add($current)
}

$relevant = foreach ($section in $sections) {
  $text = $section -join "`n"
  $heading = $section[0]
  if ($heading -match "(?i)zen|compat_proxy|兼容代理|opencode") {
    $text.TrimEnd()
  }
}

$historyHeader = @"
# codex-ui OpenCode proxy history

Extracted from ``$changelogPath``.

The source includes codex-ui commit ``$(git -C $sourceRoot rev-parse HEAD)`` and
the working tree present on 2026-10-27.

"@
Write-Utf8File (Join-Path $historyDir "CHANGELOG-opencode-proxy.md") (
  $historyHeader + ($relevant -join "`n`n") + "`n"
)

$commitPaths = @(
  "src-tauri/src/codex/zen_proxy.rs"
  "src-tauri/src/codex/zen_proxy"
  "src-tauri/src/codex/compat_proxy"
  "src-tauri/src/codex/opencode_profile.rs"
  "src-tauri/resources/opencode_tools.json"
)
$commitLines = & git -C $sourceRoot log --all --date=short `
  --format="%H`t%ad`t%s" -- @commitPaths
$commitDoc = @"
# Relevant codex-ui commits

Generated from codex-ui commit ``$(git -C $sourceRoot rev-parse HEAD)``.

| Commit | Date | Subject |
|---|---|---|
"@
foreach ($line in $commitLines) {
  $parts = $line -split "`t", 3
  if ($parts.Count -eq 3) {
    $commitDoc += "`n| ``$($parts[0])`` | $($parts[1]) | $($parts[2] -replace '\|', '\|') |"
  }
}
Write-Utf8File (Join-Path $historyDir "COMMITS.md") ($commitDoc + "`n")

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
  Where-Object {
    $relative = $_.FullName.Substring($repoRoot.Length + 1) -replace "\\", "/"
    (
      $relative -match "^(reference/codex-ui|resources|src/codex)/" -or
      $relative -eq "scripts/prepare-boringssl-tools.ps1"
    ) -and
      $relative -notmatch "(^|/)target/"
  } |
  Sort-Object FullName
$manifestFiles = foreach ($file in $files) {
  [ordered]@{
    path = $file.FullName.Substring($repoRoot.Length + 1) -replace "\\", "/"
    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    size = $file.Length
  }
}
$manifest = [ordered]@{
  source_root = $sourceRoot
  source_commit = (& git -C $sourceRoot rev-parse HEAD)
  source_working_tree_dirty = [bool](& git -C $sourceRoot status --porcelain)
  extracted_at = (Get-Date).ToString("o")
  files = @($manifestFiles)
}
Write-Utf8File (Join-Path $repoRoot "SOURCE_MANIFEST.json") (
  ($manifest | ConvertTo-Json -Depth 6) + "`n"
)

Write-Host "History and manifest extracted from $sourceRoot"
