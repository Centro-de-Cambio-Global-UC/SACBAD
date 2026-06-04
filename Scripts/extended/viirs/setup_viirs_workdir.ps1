# Prepare Output/extended/viirs/ without Python on PATH (PowerShell fallback).
# Preferred: python Scripts/extended/viirs/setup_viirs_workdir.py

param(
  [string]$RepoRoot = (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
)

$ErrorActionPreference = "Stop"
$srcShp = Join-Path $RepoRoot "Input\extended\viirs\shapefiles"
$work = Join-Path $RepoRoot "Output\extended\viirs"
$dstShp = Join-Path $work "shapefiles"

@(
  $work,
  $dstShp,
  (Join-Path $work "Download\viirs_avg_rad\raw"),
  (Join-Path $work "Download\viirs_avg_rad\cut"),
  (Join-Path $work "Download\viirs_avg_rad\background_denoise\denoise"),
  (Join-Path $work "Download\viirs_avg_rad_new_years"),
  (Join-Path $work "Download\viirs_avg_rad\cortado"),
  (Join-Path $work "output_post-processed")
) | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

foreach ($f in Get-ChildItem -LiteralPath $srcShp -File) {
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dstShp $f.Name) -Force
}

Write-Host "VIIRS work dir: $work"
Write-Host "Shapefiles copied to: $dstShp"
if (-not (Test-Path (Join-Path $dstShp "cut_area.shp"))) {
  throw "cut_area.shp missing after copy"
}
