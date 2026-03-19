<#
.SYNOPSIS
    Repair‑Workspace (V9.3.3 — Deterministic)
    1. Clears Repo B (runtime‑only mirror)
    2. Runs Preflight (relaxed Repo A + strict Repo B)
    3. Runs Sync‑Dev Apply to rebuild Repo B
#>

param(
    [string]$RepoA = $Global:PrimaryRoot,
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

Write-Host "`n>>> Repairing workspace (Clear‑RepoB + Preflight + Sync‑Dev Apply)..." -ForegroundColor Cyan

# ------------------------------------------------------------
# 1. Clear Repo B
# ------------------------------------------------------------
$cleanup = Join-Path $RepoA "scripts\forensic_suite_RepoB_cleanup.ps1"

if (!(Test-Path $cleanup)) {
    Write-Host "[ERROR] Cleanup script missing: $cleanup" -ForegroundColor Red
    exit 99
}

Write-Host "`n>>> Clearing Repo B..." -ForegroundColor Yellow
& $cleanup -RepoB $RepoB
$cleanCode = $LASTEXITCODE

if ($cleanCode -ne 0) {
    Write-Host "[ABORT] Cleanup failed with code $cleanCode." -ForegroundColor Red
    exit $cleanCode
}

# ------------------------------------------------------------
# 2. Preflight (Combined Validator)
# ------------------------------------------------------------
$preflight = Join-Path $RepoA "scripts\Invoke-Preflight.ps1"

if (!(Test-Path $preflight)) {
    Write-Host "[ERROR] Preflight script missing: $preflight" -ForegroundColor Red
    exit 98
}

Write-Host "`n>>> Running Preflight..." -ForegroundColor Yellow
& $preflight -RepoA $RepoA -RepoB $RepoB
$preCode = $LASTEXITCODE

if ($preCode -ne 0) {
    Write-Host "[ABORT] Repair blocked by Preflight failure (code $preCode)." -ForegroundColor Red
    exit $preCode
}

# ------------------------------------------------------------
# 3. Sync‑Dev Apply (rebuild Repo B)
# ------------------------------------------------------------
Write-Host "`n>>> Running Sync‑Dev Apply to rebuild Repo B..." -ForegroundColor Yellow
& (Join-Path $RepoA "scripts\Sync-DevTrees.FullSuite.ps1") -ForceApply
$syncCode = $LASTEXITCODE

if ($syncCode -ne 0) {
    Write-Host "[ABORT] Sync‑Dev Apply failed with code $syncCode." -ForegroundColor Red
    exit $syncCode
}

Write-Host "`n[SUCCESS] Workspace repaired successfully." -ForegroundColor Green
exit 0
