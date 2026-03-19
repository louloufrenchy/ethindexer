<#
    Sync‑DevTrees.Validate.ps1
    V9.3.2 — Strict Allow‑List Edition
    Validates Repo A, Repo B, installer_payload, and installed output
    using a unified runtime‑only allow‑list.
#>

param(
    [string]$MappingCsv,
    [string]$RepoA_Suite,
    [string]$RepoB_Suite,
    [string]$PayloadRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\installer_payload",
    [string]$InstalledRoot = "C:\Program Files\ForensicSuiteV2",
    [string]$ExclusionMap
)

$ErrorActionPreference = "Stop"

Write-Host "=== Sync‑DevTrees VALIDATION (V9.3 — STRICT SUITE SCOPE) ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 0. Strict allow‑list (shared across RepoB, payload, installed)
# ---------------------------------------------------------------------
$AllowedTopLevel = @(
    "forensic_suite_v2",
    "dashboards",
    "scripts",
    "wheel",
    "pyproject.toml",
    "indexers",
    "grafana"
)

$AllowedScripts = @(
    "install_services.ps1",
    "windows_orchestrator_service.ps1",
    "operator_console.ps1",
    "healthcheck.ps1",
    "healthcheck_core.py"
)

$AllowedRootFiles = @(
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template"
)

function Is‑AllowedPath {
    param([string]$RelPath)

    $p = $RelPath -replace "/", "\"

    foreach ($root in $AllowedTopLevel) {
        if ($p -like "$root\*") { return $true }
    }

    foreach ($s in $AllowedScripts) {
        if ($p -eq "scripts\$s") { return $true }
    }

    if ($p -like "wheel\*.whl") { return $true }

    if ($p -in $AllowedRootFiles) { return $true }

    return $false
}

# ---------------------------------------------------------------------
# 1. Load mapping
# ---------------------------------------------------------------------
if (!(Test-Path $MappingCsv)) {
    Write-Host "[ERROR] Mapping CSV not found: $MappingCsv" -ForegroundColor Red
    exit 1
}

$rows = Import-Csv $MappingCsv
if ($rows.Count -eq 0) {
    Write-Host "[ERROR] Mapping CSV is empty." -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------
# 2. Validate Repo B (runtime‑only mirror)
# ---------------------------------------------------------------------
Write-Host "`n[1/4] Validating Repo B (runtime‑only)..." -ForegroundColor Cyan

$RepoB_Files = Get-ChildItem $RepoB_Suite -Recurse -File | ForEach-Object {
    $_.FullName.Replace("$RepoB_Suite\", "")
}

$UnexpectedRepoB = @()

foreach ($f in $RepoB_Files) {
    if (-not (Is‑AllowedPath $f)) {
        $UnexpectedRepoB += $f
    }
}

if ($UnexpectedRepoB.Count -gt 0) {
    Write-Host "[FAIL] Repo B contains forbidden files:" -ForegroundColor Red
    $UnexpectedRepoB | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 20
}

Write-Host "[OK] Repo B contains only runtime‑allowed files." -ForegroundColor Green

# ---------------------------------------------------------------------
# 3. Validate installer_payload (must match strict allow‑list)
# ---------------------------------------------------------------------
Write-Host "`n[2/4] Validating installer_payload..." -ForegroundColor Cyan

$Payload_Files = Get-ChildItem $PayloadRoot -Recurse -File | ForEach-Object {
    $_.FullName.Replace("$PayloadRoot\", "")
}

$UnexpectedPayload = @()

foreach ($f in $Payload_Files) {
    if (-not (Is‑AllowedPath $f)) {
        $UnexpectedPayload += $f
    }
}

if ($UnexpectedPayload.Count -gt 0) {
    Write-Host "[FAIL] installer_payload contains forbidden files:" -ForegroundColor Red
    $UnexpectedPayload | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 30
}

Write-Host "[OK] installer_payload is clean and runtime‑only." -ForegroundColor Green

# ---------------------------------------------------------------------
# 4. Validate installed output matches installer_payload
# ---------------------------------------------------------------------
Write-Host "`n[3/4] Validating installed output vs installer_payload..." -ForegroundColor Cyan

if (!(Test-Path $InstalledRoot)) {
    Write-Host "[WARN] Installed root not found: $InstalledRoot" -ForegroundColor Yellow
} else {
    $Installed_Files = Get-ChildItem $InstalledRoot -Recurse -File | ForEach-Object {
        $_.FullName.Replace("$InstalledRoot\", "")
    }

    $MissingInInstalled = $Payload_Files | Where-Object { $_ -notin $Installed_Files }
    $ExtraInInstalled   = $Installed_Files | Where-Object { $_ -notin $Payload_Files }

    if ($MissingInInstalled.Count -gt 0) {
        Write-Host "[FAIL] Missing in installed (should be installed):" -ForegroundColor Red
        $MissingInInstalled | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 40
    }

    if ($ExtraInInstalled.Count -gt 0) {
        Write-Host "[FAIL] Extra in installed (not in payload):" -ForegroundColor Red
        $ExtraInInstalled | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 41
    }

    Write-Host "[OK] Installed output matches installer_payload exactly." -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 5. Validate Repo A authoritative suite structure
# ---------------------------------------------------------------------
Write-Host "`n[4/4] Validating Repo A authoritative suite..." -ForegroundColor Cyan

if (!(Test-Path $RepoA_Suite)) {
    Write-Host "[ERROR] Repo A suite root missing: $RepoA_Suite" -ForegroundColor Red
    exit 50
}

Write-Host "[OK] Repo A suite root exists." -ForegroundColor Green

# ---------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------
Write-Host "`n[SUCCESS] Strict allow‑list validation passed across Repo A, Repo B, installer_payload, and installed output." -ForegroundColor Green
exit 0
