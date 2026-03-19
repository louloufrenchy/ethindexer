<#
.SYNOPSIS
    Strict runtime‑only validator for Repo B (V9.3.4).
    Ensures Repo B contains ONLY wheel + runtime scripts + bootstrap/templates.

.DESCRIPTION
    This validator enforces the wheel‑based runtime model:
      - No source tree under forensic_suite_v2
      - No dashboards, tests, tools, plugins, grafana, indexers
      - No Makefile, setup.cfg, pyproject.toml
      - Only wheel + runtime scripts + bootstrap/templates
#>

param(
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Sync‑DevTrees VALIDATION (V9.3.4 — Runtime‑Only) ===" -ForegroundColor Cyan
Write-Host "Validating Repo B: $RepoB" -ForegroundColor Gray

# Allowed top-level files
$AllowedFiles = @(
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template",
    "__init__.py"          # NEW: allowed in V9.3.4
)

# Allowed top-level folders
$AllowedFolders = @(
    "scripts",
    "wheel"
)

# Allowed runtime scripts
$AllowedScriptFiles = @(
    "__init__.py",                     # NEW: allowed
    "db_migrate.py",
    "healthcheck.py",                  # NEW: allowed
    "healthcheck_core.py",
    "install_services.ps1",
    "operator_console.ps1",
    "operator_console.py",
    "start_all_indexers.py",
    "windows_orchestrator_service.ps1"
)

# 1. Validate top-level structure
$items = Get-ChildItem $RepoB

foreach ($item in $items) {
    if ($item.PSIsContainer) {
        if ($item.Name -notin $AllowedFolders) {
            Write-Host "[FAIL] Forbidden folder: $($item.Name)" -ForegroundColor Red
            return 1
        }
    } else {
        if ($item.Name -notin $AllowedFiles) {
            Write-Host "[FAIL] Forbidden file: $($item.Name)" -ForegroundColor Red
            return 1
        }
    }
}

# 2. Validate wheel folder
$wheelDir = Join-Path $RepoB "wheel"
if (-not (Test-Path $wheelDir)) {
    Write-Host "[FAIL] wheel folder missing." -ForegroundColor Red
    return 1
}

$wheels = @(Get-ChildItem $wheelDir -Filter "*.whl" -ErrorAction SilentlyContinue)
if ($wheels.Count -ne 1) {
    Write-Host "[FAIL] wheel folder must contain exactly one wheel." -ForegroundColor Red
    return 1
}

# 3. Validate scripts folder
$scriptsDir = Join-Path $RepoB "scripts"
if (-not (Test-Path $scriptsDir)) {
    Write-Host "[FAIL] scripts folder missing." -ForegroundColor Red
    return 1
}

foreach ($file in (Get-ChildItem $scriptsDir -File)) {
    if ($file.Name -notin $AllowedScriptFiles) {
        Write-Host "[FAIL] Forbidden runtime script: $($file.Name)" -ForegroundColor Red
        return 1
    }
}

Write-Host "[SUCCESS] Repo B is a clean runtime‑only mirror." -ForegroundColor Green
return 0
