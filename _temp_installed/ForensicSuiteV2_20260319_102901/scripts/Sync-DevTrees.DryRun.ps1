<#
.SYNOPSIS
    Dry‑run for wheel‑based runtime‑only Sync‑DevTrees (V9.3.3).
    Shows ALL scripts under forensic_suite_v2/scripts.
#>

$RepoA = $Global:PrimaryRoot

Write-Host "=== Sync‑DevTrees DRY RUN (V9.3.3 — Runtime‑Only) ===" -ForegroundColor Cyan
Write-Host "Repo A: $RepoA" -ForegroundColor Gray

# Wheel
$dist = Join-Path $RepoA "dist"
$wheel = Get-ChildItem $dist -Filter "forensic_suite_v2-*.whl" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Write-Host ""
Write-Host "Wheel to copy:" -ForegroundColor Cyan
Write-Host "  $($wheel.Name)"

# Scripts
$srcScriptsRoot = Join-Path $RepoA "forensic_suite_v2\scripts"
$allScripts = Get-ChildItem $srcScriptsRoot -File -Recurse |
              Where-Object { $_.Extension -in ".py", ".ps1" }

Write-Host ""
Write-Host "Runtime scripts to copy (ALL):" -ForegroundColor Cyan

foreach ($src in $allScripts) {
    Write-Host "  $($src.Name)"
}

Write-Host ""
Write-Host "[INFO] Dry‑run complete. No changes made." -ForegroundColor Green
