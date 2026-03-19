# =====================================================================
# FILE: scripts\forensic_suite_RepoA_validator_v2.ps1
# =====================================================================
# Repo A Validator v2 (Authoritative Development + Installer Pipeline)
# =====================================================================

param(
    [string]$RepoA_Root  = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$SuiteFolder = "forensic_suite_v2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Repo A Validator v2 (Authoritative Development + Installer Pipeline) ===" -ForegroundColor Cyan

if (!(Test-Path $RepoA_Root)) {
    Write-Host "[ERROR] Repo A root not found: $RepoA_Root" -ForegroundColor Red
    exit 1
}

$RepoA_Suite = Join-Path $RepoA_Root $SuiteFolder
if (!(Test-Path $RepoA_Suite)) {
    Write-Host "[ERROR] Repo A suite folder not found: $RepoA_Suite" -ForegroundColor Red
    exit 2
}

# Basic checks: required files/folders in Repo A root
$requiredRoot = @(
    "scripts",
    "forensic_suite_v2",
    "Output",
    "installer_payload",
    "build_final.ps1",
    "build_and_deploy.ps1",
    "refresh_installer_payload.ps1",
    "post_install_validation.ps1"
)

$missingRoot = @()
foreach ($r in $requiredRoot) {
    $p = Join-Path $RepoA_Root $r
    if (!(Test-Path $p)) {
        $missingRoot += $r
    }
}

if ($missingRoot.Count -gt 0) {
    Write-Host "[FAIL] Repo A is missing required items:" -ForegroundColor Red
    $missingRoot | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 3
}

Write-Host "[OK] Repo A root structure looks valid." -ForegroundColor Green

# Optional: simple sanity check on suite contents (exists, non-empty)
$files = Get-ChildItem -Path $RepoA_Suite -Recurse -File
if ($files.Count -eq 0) {
    Write-Host "[ERROR] Repo A suite appears empty: $RepoA_Suite" -ForegroundColor Red
    exit 4
}

Write-Host "[SUCCESS] Repo A is clean, authoritative, and ready for Sync‑Dev / Build‑Suite." -ForegroundColor Green
exit 0
