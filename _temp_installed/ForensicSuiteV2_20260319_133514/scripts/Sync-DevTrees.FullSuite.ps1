<#
.SYNOPSIS
    Full Sync-Dev pipeline for Repo A -> Repo B runtime-only mirror.

.DESCRIPTION
    V9.3.9 hardened flow:

      1. Validate Repo A only
      2. Clean Repo B
      3. Validate Repo B empty/pre-sync state
      4. Dry-run
      5. Apply
      6. Validate final Repo B populated state

.NOTES
    This version avoids argument-binding issues by calling the Repo B
    validator directly when named parameters are needed.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot = if ($Global:PrimaryRoot) {
    $Global:PrimaryRoot
}
else {
    "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
}

$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"

$RepoAValidator = Join-Path $RepoRoot "scripts\forensic_suite_RepoA_validator_v2.ps1"
$RepoBCleanup   = Join-Path $RepoRoot "scripts\forensic_suite_RepoB_cleanup.ps1"
$RepoBValidator = Join-Path $RepoRoot "scripts\forensic_suite_RepoB_validator.ps1"
$DryRunScript   = Join-Path $RepoRoot "scripts\Sync-DevTrees.DryRun.ps1"
$ApplyScript    = Join-Path $RepoRoot "scripts\Sync-DevTrees.Apply.ps1"
$ValidateScript = Join-Path $RepoRoot "scripts\Sync-DevTrees.Validate.ps1"

function Invoke-StepScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$StepName = $(Split-Path $Path -Leaf)
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Missing script for step '$StepName': $Path" -ForegroundColor Red
        return 97
    }

    & $Path
    $code = $LASTEXITCODE

    if ($null -eq $code) {
        $code = 0
    }

    return ([int]$code)
}

Write-Host "=== Sync-DevTrees FULL SUITE (V9.3.9 - Runtime-Only, Hardened) ===" -ForegroundColor Cyan
Write-Host "Repo A: $RepoRoot" -ForegroundColor Gray
Write-Host "Repo B: $RepoB" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 1. Validate Repo A only
# ---------------------------------------------------------------------
Write-Host ">>> Step 1/6: Validate Repo A..." -ForegroundColor Yellow

$repoACode = Invoke-StepScript `
    -Path $RepoAValidator `
    -StepName "Repo A Validator"

if ($repoACode -ne 0) {
    Write-Host "[ABORT] Repo A validation failed with code $repoACode." -ForegroundColor Red
    exit $repoACode
}

Write-Host "[OK] Repo A validation passed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 2. Clean Repo B first
# ---------------------------------------------------------------------
Write-Host ">>> Step 2/6: Clean Repo B..." -ForegroundColor Yellow

$cleanupCode = Invoke-StepScript `
    -Path $RepoBCleanup `
    -StepName "Repo B Cleanup"

if ($cleanupCode -ne 0) {
    Write-Host "[ABORT] Repo B cleanup failed with code $cleanupCode." -ForegroundColor Red
    exit $cleanupCode
}

Write-Host "[OK] Repo B cleanup completed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 3. Validate Repo B empty/pre-sync state
# ---------------------------------------------------------------------
Write-Host ">>> Step 3/6: Validate Repo B empty/pre-sync state..." -ForegroundColor Yellow

if (-not (Test-Path $RepoBValidator)) {
    Write-Host "[ERROR] Missing Repo B validator: $RepoBValidator" -ForegroundColor Red
    exit 97
}

& $RepoBValidator -RepoB $RepoB -PreSync
$repoBPreCode = $LASTEXITCODE
if ($null -eq $repoBPreCode) {
    $repoBPreCode = 0
}
$repoBPreCode = [int]$repoBPreCode

if ($repoBPreCode -ne 0) {
    Write-Host "[ABORT] Repo B pre-sync validation failed with code $repoBPreCode." -ForegroundColor Red
    exit $repoBPreCode
}

Write-Host "[OK] Repo B pre-sync validation passed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 4. Dry-run
# ---------------------------------------------------------------------
Write-Host ">>> Step 4/6: Dry-run..." -ForegroundColor Yellow

$dryCode = Invoke-StepScript `
    -Path $DryRunScript `
    -StepName "Sync-DevTrees.DryRun"

if ($dryCode -ne 0) {
    Write-Host "[ABORT] Dry-run failed with code $dryCode." -ForegroundColor Red
    exit $dryCode
}

Write-Host "[OK] Dry-run completed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 5. Apply
# ---------------------------------------------------------------------
Write-Host ">>> Step 5/6: Apply runtime-only mirror..." -ForegroundColor Yellow

$applyCode = Invoke-StepScript `
    -Path $ApplyScript `
    -StepName "Sync-DevTrees.Apply"

if ($applyCode -ne 0) {
    Write-Host "[ABORT] Apply failed with code $applyCode." -ForegroundColor Red
    exit $applyCode
}

Write-Host "[OK] Apply completed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 6. Validate final populated Repo B
# ---------------------------------------------------------------------
Write-Host ">>> Step 6/6: Validate populated Repo B..." -ForegroundColor Yellow

if (Test-Path $ValidateScript) {
    $finalCode = Invoke-StepScript `
        -Path $ValidateScript `
        -StepName "Sync-DevTrees.Validate"
}
else {
    if (-not (Test-Path $RepoBValidator)) {
        Write-Host "[ERROR] Missing Repo B validator: $RepoBValidator" -ForegroundColor Red
        exit 97
    }

    & $RepoBValidator -RepoB $RepoB
    $finalCode = $LASTEXITCODE
    if ($null -eq $finalCode) {
        $finalCode = 0
    }
    $finalCode = [int]$finalCode
}

if ($finalCode -ne 0) {
    Write-Host "[ABORT] Final Repo B validation failed with code $finalCode." -ForegroundColor Red
    exit $finalCode
}

Write-Host ""
Write-Host "[SUCCESS] Full Sync-DevTrees pipeline completed." -ForegroundColor Green
exit 0
