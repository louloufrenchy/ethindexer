# =====================================================================
# FILE: scripts\forensic_suite_RepoB_validator.ps1
# =====================================================================
# Repo B Validator (Runtime-Only Integrity Check)
# =====================================================================

param(
    [string]$RepoB_Root  = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [string]$SuiteFolder = "forensic_suite_v2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Repo B Validator (Runtime‑Only Integrity Check) ===" -ForegroundColor Cyan

if (!(Test-Path $RepoB_Root)) {
    Write-Host "[ERROR] Repo B root not found: $RepoB_Root" -ForegroundColor Red
    exit 1
}

$RepoB_Suite = Join-Path $RepoB_Root $SuiteFolder
if (!(Test-Path $RepoB_Suite)) {
    Write-Host "[ERROR] Repo B suite root not found: $RepoB_Suite" -ForegroundColor Red
    exit 2
}

# NEW: Allow bootstrap if suite folder exists but is empty
$items = Get-ChildItem -Path $RepoB_Suite -Force -ErrorAction SilentlyContinue
if ($items.Count -eq 0) {
    Write-Host "[OK] Repo B suite root exists but is empty — bootstrap mode allowed." -ForegroundColor Yellow
    exit 0
}

$allowed = @(
    "forensic_suite_v2",
    "grafana",
    "indexers",
    "pyproject.toml",
    "requirements.txt"
)

$items = Get-ChildItem -LiteralPath $RepoB_Root
$contamination = @()

foreach ($item in $items) {
    if ($allowed -notcontains $item.Name) {
        $contamination += $item.Name
    }
}

if ($contamination.Count -gt 0) {
    Write-Host "[FAIL] Repo B contains contamination:" -ForegroundColor Red
    foreach ($c in $contamination) {
        Write-Host " - Unexpected top‑level item: $c" -ForegroundColor Red
    }
    exit 3
}

Write-Host "[OK] Repo B top-level structure is runtime-only." -ForegroundColor Green
exit 0
