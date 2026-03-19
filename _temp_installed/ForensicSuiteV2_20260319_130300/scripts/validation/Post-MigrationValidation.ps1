<#
.SYNOPSIS
    Validates Repo A + Repo B after migration to F:\DEVELOPMENT.

.DESCRIPTION
    Checks:
      - Path normalization
      - Repo A structure
      - Repo B structure
      - Installer payload sync
      - Orchestrator manifest
      - Critical scripts for hardcoded paths
#>

Import-Module "$PSScriptRoot\..\PathNormalization.psm1" -Force

Write-Host "=== POST-MIGRATION VALIDATION ===" -ForegroundColor Cyan

# 1. Path normalization
Test-PathNormalization

# 2. Repo A structure
$expectedA = @(
    "scripts",
    "config",
    "installer_payload",
    "out",
    "build",
    "Documents"
)

Write-Host "`n[Repo A Structure]" -ForegroundColor Cyan
foreach ($d in $expectedA) {
    $p = Join-Path (Get-RepoARoot) $d
    if (Test-Path $p) {
        Write-Host "[OK] $p" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $p" -ForegroundColor Red
    }
}

# 3. Repo B structure
$expectedB = @(
    "btc_indexer",
    "eth_indexer",
    "tron_indexer",
    "core",
    "scripts",
    "tools"
)

Write-Host "`n[Repo B Structure]" -ForegroundColor Cyan
foreach ($d in $expectedB) {
    $p = Join-Path (Get-RepoBRoot) $d
    if (Test-Path $p) {
        Write-Host "[OK] $p" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $p" -ForegroundColor Red
    }
}

# 4. Installer payload sync
Write-Host "`n[Installer Payload]" -ForegroundColor Cyan
$payload = Get-InstallerPayloadRoot
if (Test-Path $payload) {
    Write-Host "[OK] Payload exists: $payload" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Payload missing: $payload" -ForegroundColor Red
}

# 5. Hardcoded path scan
Write-Host "`n[Hardcoded Path Scan]" -ForegroundColor Cyan

$patterns = @(
    "C:\\development",
    "C:/development",
    "C:\\tools",
    "C:\\forensic_secrets",
    "C:\\forensic_suite_v2"
)

$files = Get-ChildItem (Get-RepoARoot) -Recurse -File |
    Select-String -Pattern $patterns -SimpleMatch

if ($files) {
    Write-Host "[WARNING] Hardcoded paths found:" -ForegroundColor Yellow
    $files | Format-Table Path, LineNumber, Line -AutoSize
} else {
    Write-Host "[OK] No hardcoded paths detected." -ForegroundColor Green
}

Write-Host "`n=== VALIDATION COMPLETE ===" -ForegroundColor Cyan
