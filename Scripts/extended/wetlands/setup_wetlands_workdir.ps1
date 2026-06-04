# Prepare Output/extended/wetlands/ for GEE notebooks (relative paths only).
param(
  [string]$RepoRoot = (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
)

$ErrorActionPreference = "Stop"
$srcShapes = Join-Path $RepoRoot "Input\extended\wetlands\shapes"
$work = Join-Path $RepoRoot "Output\extended\wetlands"
$dstShapes = Join-Path $work "shapes"
$download = Join-Path $work "Download\ligua_petorca_sentinel_TOA"

New-Item -ItemType Directory -Path $dstShapes -Force | Out-Null
New-Item -ItemType Directory -Path $download -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcShapes "*") -Destination $dstShapes -Recurse -Force

Write-Host "Wetlands work dir: $work"
Write-Host "Run notebook with cwd = Output/extended/wetlands"
Write-Host "Set GEE_PROJECT env var if your Earth Engine project id is required."
