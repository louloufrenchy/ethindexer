<#
.SYNOPSIS
    Repo B Validator (Runtime-Only Integrity Check, V9.3.7)

.DESCRIPTION
    Valid states:
      1. Repo B missing           -> FAIL
      2. Repo B exists but empty  -> PASS (pre-sync state)
      3. Repo B populated and valid runtime-only mirror -> PASS

    Modes:
      -PreSync  : validate only that Repo B is empty/cleanable
      default   : validate fully populated runtime-only mirror

    Benign residue tolerated:
      - logs
#>

[CmdletBinding()]
param(
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [switch]$PreSync
)

$ErrorActionPreference = "Stop"

Write-Host "=== Repo B Validator (Runtime-Only Integrity Check, V9.3.7) ==="
Write-Host "Validating Repo B: $RepoB"

# ---------------------------------------------------------------------
# 1. Repo B root must exist
# ---------------------------------------------------------------------
if (-not (Test-Path $RepoB)) {
    Write-Host "[ERROR] Repo B suite root not found: $RepoB" -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------
# 2. Collect top-level items robustly
# ---------------------------------------------------------------------
$topLevelItems = @(
    Get-ChildItem -Path $RepoB -Force -ErrorAction SilentlyContinue |
    Where-Object { $null -ne $_ }
)

$AllowedTop = @(
    "scripts",
    "wheel",
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template"
)

$IgnoredTop = @(
    "logs"
)

$Forbidden = @(
    "forensic_suite_v2",
    "grafana",
    "indexers",
    "core",
    "plugins",
    "dashboards",
    "tests",
    "tools",
    "__init__.py",
    "Makefile",
    "setup.cfg",
    "venv",
    "Output",
    "build",
    "dist"
)

# ---------------------------------------------------------------------
# 3. Pre-sync mode: Repo B must be empty except benign residue
# ---------------------------------------------------------------------
if ($PreSync) {

    if ($topLevelItems.Count -eq 0) {
        Write-Host "[INFO] Repo B is empty; treating as clean pre-sync state." -ForegroundColor Yellow
        exit 0
    }

    $meaningfulItems = @(
        $topLevelItems | Where-Object { $IgnoredTop -notcontains $_.Name }
    )

    if ($meaningfulItems.Count -eq 0) {
        Write-Host "[INFO] Repo B contains only benign residue; treating as clean pre-sync state." -ForegroundColor Yellow
        exit 0
    }

    foreach ($item in $meaningfulItems) {
        Write-Host "[FAIL] Repo B is not empty before sync: $($item.Name)" -ForegroundColor Red
    }

    Write-Host "[FAIL] Repo B pre-sync validation failed." -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------
# 4. Normal full validation mode
# ---------------------------------------------------------------------
if ($topLevelItems.Count -eq 0) {
    Write-Host "[INFO] Repo B is empty; treating as clean pre-sync state." -ForegroundColor Yellow
    exit 0
}

$fail = $false

foreach ($item in $topLevelItems) {

    if ($IgnoredTop -contains $item.Name) {
        Write-Host "[INFO] Ignoring benign runtime residue: $($item.Name)" -ForegroundColor Yellow
        continue
    }

    if ($Forbidden -contains $item.Name) {
        Write-Host "[FAIL] Forbidden item present: $($item.Name)" -ForegroundColor Red
        $fail = $true
        continue
    }

    if ($AllowedTop -notcontains $item.Name) {
        Write-Host "[FAIL] Unexpected top-level item: $($item.Name)" -ForegroundColor Red
        $fail = $true
    }
}

$Required = @(
    "scripts",
    "wheel",
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template"
)

foreach ($req in $Required) {
    $path = Join-Path $RepoB $req
    if (-not (Test-Path $path)) {
        Write-Host "[FAIL] Missing required item: $req" -ForegroundColor Red
        $fail = $true
    }
}

$scripts = Join-Path $RepoB "scripts"
if (Test-Path $scripts) {

    $RequiredScripts = @(
        "__init__.py",
        "db_migrate.py",
        "healthcheck.py",
        "healthcheck_core.py",
        "install_services.ps1",
        "install_services.py",
        "operator_console.ps1",
        "operator_console.py",
        "start_all_indexers.py",
        "windows_orchestrator_service.ps1"
    )

    foreach ($rs in $RequiredScripts) {
        $p = Join-Path $scripts $rs
        if (-not (Test-Path $p)) {
            Write-Host "[WARN] Missing runtime script: $rs" -ForegroundColor Yellow
        }
    }
}

$wheelDir = Join-Path $RepoB "wheel"
if (Test-Path $wheelDir) {
    $wheel = Get-ChildItem $wheelDir -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $wheel) {
        Write-Host "[FAIL] No forensic_suite_v2 wheel found in wheel\" -ForegroundColor Red
        $fail = $true
    }
}
else {
    Write-Host "[FAIL] Missing wheel folder." -ForegroundColor Red
    $fail = $true
}

if ($fail) {
    Write-Host "[FAIL] Repo B validation failed." -ForegroundColor Red
    exit 2
}

Write-Host "[OK] Repo B is clean." -ForegroundColor Green
exit 0
