<#
.SYNOPSIS
    Preflight Wrapper (V9.3.3 — Relaxed Dev Mode)
    Uses the unified Combined Validator.
#>

param(
    [string]$RepoA = $Global:PrimaryRoot,
    [string]$RepoB = $Global:RepoB
)

Write-Host "`n>>> Running Preflight (Repo A + Repo B validators)..." -ForegroundColor Cyan

$Combined = Join-Path $Global:PrimaryRoot "scripts\forensic_suite_Combined_validator.ps1"

if (!(Test-Path $Combined)) {
    Write-Host "[ERROR] Combined validator not found: $Combined" -ForegroundColor Red
    exit 99
}

& $Combined -RepoA $RepoA -RepoB $RepoB
$code = $LASTEXITCODE

if ($code -ne 0) {
    Write-Host "[BLOCKED] Preflight failed with code $code." -ForegroundColor Red
    exit $code
}

Write-Host "[OK] Preflight passed." -ForegroundColor Green
exit 0
