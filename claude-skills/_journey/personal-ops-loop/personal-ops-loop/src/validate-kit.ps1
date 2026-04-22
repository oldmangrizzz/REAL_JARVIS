param(
  [string]$KitRoot = "personal-ops-loop"
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
  (Join-Path $KitRoot 'SKILL.md'),
  (Join-Path $KitRoot 'references\implementation-guide.md'),
  (Join-Path $KitRoot 'references\distinct-positioning.md'),
  (Join-Path $KitRoot 'assets\templates\HEARTBEAT.md'),
  (Join-Path $KitRoot 'assets\templates\MEMORY.md'),
  (Join-Path $KitRoot 'assets\templates\heartbeat-state.json')
)

foreach ($file in $requiredFiles) {
  if (-not (Test-Path $file)) {
    Write-Output "MISSING_FILE: $file"
    exit 1
  }
}

$kitPath = 'kit.md'
if (-not (Test-Path $kitPath)) {
  Write-Output 'MISSING_FILE: kit.md'
  exit 1
}

$content = Get-Content $kitPath -Raw
$sections = @(
  '## Goal',
  '## When to Use',
  '## Setup',
  '## Steps',
  '## Constraints',
  '## Safety Notes'
)
foreach ($section in $sections) {
  if ($content -notmatch [regex]::Escape($section)) {
    Write-Output "MISSING_SECTION: $section"
    exit 1
  }
}

if ($content -notmatch 'schema:\s*kit/1\.0') {
  Write-Output 'MISSING_OR_INVALID_SCHEMA'
  exit 1
}

Write-Output 'VALID'
