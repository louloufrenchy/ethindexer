<#
    Compare‑StatusReport.ps1
    V9.3.2 — Strict Allow‑List Edition
    Compares cluster nodes against each other AND against the runtime‑only allow‑list.
#>

param(
    [string]$HostList = "F:\tools\forensic_hosts.txt",
    [string]$RepoB_Root = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [string]$InstalledRoot = "C:\Program Files\ForensicSuiteV2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Compare‑StatusReport (Strict Allow‑List, V9.3.2) ===" -ForegroundColor Cyan

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
# 1. Load host list
# ---------------------------------------------------------------------
if (!(Test-Path $HostList)) {
    Write-Host "[ERROR] Host list not found: $HostList" -ForegroundColor Red
    exit 1
}

$Hosts = Get-Content $HostList | Where-Object { $_.Trim() -ne "" }

if ($Hosts.Count -eq 0) {
    Write-Host "[ERROR] Host list is empty." -ForegroundColor Red
    exit 2
}

Write-Host "[INFO] Hosts loaded: $($Hosts -join ', ')" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 2. Gather file lists from each host (runtime‑only)
# ---------------------------------------------------------------------
$ClusterFiles = @{}

foreach ($host in $Hosts) {
    Write-Host "`n>>> Gathering file list from $host ..." -ForegroundColor Cyan

    $cmd = "Get-ChildItem '$InstalledRoot' -Recurse -File | ForEach-Object { `$_.FullName.Replace('$InstalledRoot\', '') }"
    $files = Invoke-Command -ComputerName $host -ScriptBlock { param($c) Invoke-Expression $c } -ArgumentList $cmd

    $Allowed = @()
    $Forbidden = @()

    foreach ($f in $files) {
        if (Is‑AllowedPath $f) {
            $Allowed += $f
        } else {
            $Forbidden += $f
        }
    }

    $ClusterFiles[$host] = [PSCustomObject]@{
        Allowed   = $Allowed
        Forbidden = $Forbidden
    }

    if ($Forbidden.Count -gt 0) {
        Write-Host "[WARN] Forbidden files found on $host:" -ForegroundColor Yellow
        $Forbidden | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    } else {
        Write-Host "[OK] $host contains only runtime‑allowed files." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------
# 3. Cross‑node drift detection
# ---------------------------------------------------------------------
Write-Host "`n=== Cluster Drift Detection ===" -ForegroundColor Cyan

$BaselineHost = $Hosts[0]
$Baseline = $ClusterFiles[$BaselineHost].Allowed

foreach ($host in $Hosts) {
    if ($host -eq $BaselineHost) { continue }

    Write-Host "`n>>> Comparing $host against baseline $BaselineHost ..." -ForegroundColor Cyan

    $Current = $ClusterFiles[$host].Allowed

    $Missing = $Baseline | Where-Object { $_ -notin $Current }
    $Extra   = $Current  | Where-Object { $_ -notin $Baseline }

    if ($Missing.Count -eq 0 -and $Extra.Count -eq 0) {
        Write-Host "[OK] $host matches baseline exactly." -ForegroundColor Green
    } else {
        Write-Host "[DRIFT] Differences detected on $host:" -ForegroundColor Red

        if ($Missing.Count -gt 0) {
            Write-Host "  Missing files:" -ForegroundColor Red
            $Missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }

        if ($Extra.Count -gt 0) {
            Write-Host "  Extra files:" -ForegroundColor Red
            $Extra | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }
    }
}

# ---------------------------------------------------------------------
# 4. Final summary
# ---------------------------------------------------------------------
Write-Host "`n[SUCCESS] Strict allow‑list cluster drift detection complete." -ForegroundColor Green
Write-Host "Baseline host: $BaselineHost" -ForegroundColor Gray
exit 0
