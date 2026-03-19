# =====================================================================
# FILE: scripts\Sync-DevTrees.FullSuite.ps1
# =====================================================================
# Sync‑DevTrees.FullSuite.ps1 (V9.3)
# Full Pipeline Wrapper: DryRun → Apply → Validate
# Authoritative → Runtime‑Only Sync with Exclusion Map + Atomic Swap
# =====================================================================

param(
    [string]$MappingCsv   = "F:\tools\repo_mapping_suite.csv",
    [string]$ExclusionMap = "F:\tools\sync_dev_exclusions_v9.3.yaml",
    [string]$RepoA_Root   = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$RepoB_Root   = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [switch]$ForceApply
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$RepoA_Suite = Join-Path $RepoA_Root "forensic_suite_v2"
$RepoB_Suite = Join-Path $RepoB_Root "forensic_suite_v2"

Write-Host "=== Sync‑DevTrees FULL SUITE (V9.3) ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 0. PRE-FLIGHT VALIDATION (Repo A + Repo B)
# ---------------------------------------------------------------------
Write-Host "`n>>> Running Preflight (Repo A + Repo B validators)..." -ForegroundColor Cyan
& "$ScriptRoot\forensic_suite_Combined_validator.ps1"
$pre = $LASTEXITCODE

if ($pre -ne 0) {
    Write-Host "[BLOCKED] Preflight failed. Resolve issues before syncing." -ForegroundColor Red
    exit $pre
}

Write-Host "[OK] Preflight passed." -ForegroundColor Green

# ---------------------------------------------------------------------
# 1. REGENERATE MAPPING (V9.3)
# ---------------------------------------------------------------------
Write-Host "`n>>> Regenerating Repo Mapping (V9.3)..." -ForegroundColor Cyan
& "$RepoA_Root\scripts\forensic_suite_repo_mapping.ps1" -RepoA $RepoA_Root -RepoB $RepoB_Root -OutCsv $MappingCsv -ExclusionMap $ExclusionMap
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Mapping generation failed." -ForegroundColor Red
    exit 101
}

# ---------------------------------------------------------------------
# 2. DRY RUN (V9.3)
# ---------------------------------------------------------------------
Write-Host "`n>>> Performing Sync‑Dev DRY RUN (V9.3)..." -ForegroundColor Cyan
& "$RepoA_Root\scripts\Sync-DevTrees.DryRun.ps1" -MappingCsv $MappingCsv
if ($LASTEXITCODE -ne 0) {
    Write-Host "[BLOCKED] Dry-run reported issues. Fix before applying." -ForegroundColor Red
    exit 102
}

if (-not $ForceApply) {
    Write-Host "`n[INFO] Dry-run complete. Re-run with -ForceApply to commit changes." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------
# 3. APPLY (V9.3, ATOMIC MIRROR)
# ---------------------------------------------------------------------
$TempRoot = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2_tmp"
Write-Host "`n>>> Building atomic temp mirror at $TempRoot..." -ForegroundColor Cyan

if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $TempRoot | Out-Null

& "$RepoA_Root\scripts\Sync-DevTrees.Apply.ps1" -MappingCsv $MappingCsv -TargetRoot $TempRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Apply into temp root failed." -ForegroundColor Red
    exit 103
}

# ---------------------------------------------------------------------
# 4. ATOMIC SWAP INTO REPO B
# ---------------------------------------------------------------------
Write-Host "`n>>> Performing atomic swap into Repo B..." -ForegroundColor Cyan

$BackupRoot = "F:\tools\RepoB_Backups\RepoB_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$BackupDir  = Split-Path $BackupRoot -Parent
if (!(Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

if (Test-Path $RepoB_Root) {
    Write-Host "[BACKUP] Creating backup at $BackupRoot ..." -ForegroundColor Yellow
    Rename-Item -Path $RepoB_Root -NewName (Split-Path $BackupRoot -Leaf)
    Write-Host "[BACKUP COMPLETE]" -ForegroundColor Green
}

Rename-Item -Path $TempRoot -NewName (Split-Path $RepoB_Root -Leaf)

Write-Host "[SUCCESS] Repo B updated atomically." -ForegroundColor Green
Write-Host "Backup stored at: $BackupRoot" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 5. VALIDATE FINAL STATE (V9.3)
# ---------------------------------------------------------------------
Write-Host "`n>>> Validating final Repo B state (V9.3)..." -ForegroundColor Cyan
& "$RepoA_Root\scripts\Sync-DevTrees.Validate.ps1" -MappingCsv $MappingCsv -RepoA_Suite $RepoA_Suite -RepoB_Suite $RepoB_Suite -ExclusionMap $ExclusionMap
$val = $LASTEXITCODE

if ($val -ne 0) {
    Write-Host "[ERROR] Final validation failed. Repo B may be inconsistent." -ForegroundColor Red
    exit 104
}

Write-Host "`n[SUCCESS] Full Sync‑DevTrees pipeline completed successfully (V9.3)." -ForegroundColor Green
Write-Host "Repo B is now a clean, runtime‑only mirror of Repo A." -ForegroundColor Green

exit 0
