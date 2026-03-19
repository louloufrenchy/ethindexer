<#
.SYNOPSIS
    Combined Repo A + Repo B Validator (V9.3.3 — Relaxed Dev Mode)
    Repo A = full development workspace (allowed to contain ANYTHING)
    Repo B = strict runtime‑only mirror (must match wheel‑based model)
#>

param(
    [string]$RepoA = $Global:PrimaryRoot,
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

Write-Host "=== Combined Repo A + Repo B Validator ==="

# =====================================================================
# 1. VALIDATE REPO A (Relaxed Development Mode)
# =====================================================================

Write-Host "`n>>> Validating Repo A (development workspace)..." -ForegroundColor Cyan

$RequiredA = @(
    "forensic_suite_v2",
    "scripts",
    "dist",
    "installer_payload",
    "Output",
    "pyproject.toml"
)

$failA = $false

foreach ($req in $RequiredA) {
    $path = Join-Path $RepoA $req
    if (!(Test-Path $path)) {
        Write-Host "[FAIL] Repo A missing required item: $req" -ForegroundColor Red
        $failA = $true
    }
}

if ($failA) {
    Write-Host "[FAIL] Repo A validation failed." -ForegroundColor Red
    return 1
}

Write-Host "[OK] Repo A is valid (development mode)." -ForegroundColor Green

# =====================================================================
# 2. VALIDATE REPO B (Strict Runtime‑Only Mirror)
# =====================================================================

Write-Host "`n>>> Validating Repo B (runtime mirror)..." -ForegroundColor Cyan

if (!(Test-Path $RepoB)) {
    Write-Host "[ERROR] Repo B suite root not found: $RepoB" -ForegroundColor Red
    return 2
}

# Allow empty Repo B (pre‑sync state)
$items = Get-ChildItem $RepoB -Recurse -File -ErrorAction SilentlyContinue
if (-not $items) {
    Write-Host "[INFO] Repo B is empty; treating as clean pre-sync state." -ForegroundColor Yellow
    return 0
}

# Delegate to the updated Repo B validator
$repoBValidator = Join-Path $RepoA "scripts\forensic_suite_RepoB_validator.ps1"

if (!(Test-Path $repoBValidator)) {
    Write-Host "[ERROR] Repo B validator missing: $repoBValidator" -ForegroundColor Red
    return 2
}

& $repoBValidator
return $LASTEXITCODE
