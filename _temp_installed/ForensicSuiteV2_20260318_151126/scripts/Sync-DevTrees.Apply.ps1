<#
.SYNOPSIS
    Sync‑DevTrees APPLY (V9.3.3 — Runtime‑Only)
    Copies wheel + ALL runtime scripts into Repo B (flattened).
#>

param(
    [string]$RepoA = $Global:PrimaryRoot,
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Sync‑DevTrees APPLY (V9.3.3 — Runtime‑Only) ===" -ForegroundColor Cyan
Write-Host "Repo A (authoritative root): $RepoA" -ForegroundColor Gray
Write-Host "Repo B (mirror root)      : $RepoB" -ForegroundColor Gray

# Ensure RepoB exists
if (!(Test-Path $RepoB)) {
    New-Item -ItemType Directory -Path $RepoB | Out-Null
}

# Ensure RepoB/scripts exists
$RepoBScripts = Join-Path $RepoB "scripts"
if (!(Test-Path $RepoBScripts)) {
    New-Item -ItemType Directory -Path $RepoBScripts | Out-Null
}

# Ensure RepoB/wheel exists
$RepoBWheel = Join-Path $RepoB "wheel"
if (!(Test-Path $RepoBWheel)) {
    New-Item -ItemType Directory -Path $RepoBWheel | Out-Null
}

# 1. Copy wheel
$dist = Join-Path $RepoA "dist"
$wheel = Get-ChildItem $dist -Filter "forensic_suite_v2-*.whl" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $wheel) {
    Write-Host "[ERROR] No wheel found in dist folder." -ForegroundColor Red
    exit 1
}

Write-Host "[COPY] Wheel: $($wheel.Name)" -ForegroundColor Green
Copy-Item $wheel.FullName $RepoBWheel -Force

# 2. Copy anchors (bootstrap + templates)
$anchors = @(
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template"
)

foreach ($file in $anchors) {
    $src = Join-Path $RepoA $file
    if (Test-Path $src) {
        Write-Host "[COPY] $file" -ForegroundColor Green
        Copy-Item $src (Join-Path $RepoB $file) -Force
    } else {
        Write-Host "[WARN] Missing anchor: $file" -ForegroundColor Yellow
    }
}

# 3. Copy ALL runtime scripts (flattened)
$srcScriptsRoot = Join-Path $RepoA "forensic_suite_v2\scripts"

if (!(Test-Path $srcScriptsRoot)) {
    Write-Host "[ERROR] Source scripts folder missing: $srcScriptsRoot" -ForegroundColor Red
    exit 2
}

$allScripts = Get-ChildItem $srcScriptsRoot -File -Recurse |
              Where-Object { $_.Extension -in ".py", ".ps1" }

foreach ($src in $allScripts) {
    $dest = Join-Path $RepoBScripts $src.Name
    Write-Host "[COPY] script: $($src.Name)" -ForegroundColor Green
    Copy-Item $src.FullName $dest -Force
}

Write-Host ""
Write-Host "[SUCCESS] Repo B updated to strict runtime‑only mirror (ALL scripts)." -ForegroundColor Green
exit 0
