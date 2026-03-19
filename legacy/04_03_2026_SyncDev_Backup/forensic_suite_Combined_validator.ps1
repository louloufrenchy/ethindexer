# =====================================================================
# Combined Repo A + Repo B Validator (V9.3)
# =====================================================================

param(
    [string]$RepoA_Root  = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$RepoB_Root  = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [string]$SuiteFolder = "forensic_suite_v2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Combined Repo A + Repo B Validator ===" -ForegroundColor Cyan

# ---------------------------------------------------------
# Validate Repo A
# ---------------------------------------------------------
Write-Host "`n>>> Validating Repo A (authoritative)..." -ForegroundColor Cyan
& "$RepoA_Root\scripts\forensic_suite_RepoA_validator_v2.ps1" -RepoA_Root $RepoA_Root
$codeA = $LASTEXITCODE

if ($codeA -ne 0) {
    Write-Host "[FAIL] Repo A validation failed with code $codeA." -ForegroundColor Red
} else {
    Write-Host "[OK] Repo A is clean." -ForegroundColor Green
}

# ---------------------------------------------------------
# Validate Repo B
# ---------------------------------------------------------
Write-Host "`n>>> Validating Repo B (runtime mirror)..." -ForegroundColor Cyan

& "$ScriptRoot\forensic_suite_RepoB_validator.ps1" `
    -RepoB_Root $RepoB_Root `
    -SuiteFolder $SuiteFolder

$codeB = $LASTEXITCODE

if ($codeB -ne 0) {
    Write-Host "[FAIL] Repo B validation failed with code $codeB." -ForegroundColor Red
} else {
    Write-Host "[OK] Repo B is clean." -ForegroundColor Green
}

# ---------------------------------------------------------
# Final result
# ---------------------------------------------------------
if ($codeA -eq 0 -and $codeB -eq 0) {
    Write-Host "`n[SUCCESS] Combined validation passed." -ForegroundColor Green
    exit 0
}

Write-Host "`n[BLOCKED] One or more repos are not clean. Fix before continuing." -ForegroundColor Red
exit 10
