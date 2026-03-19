<#
.SYNOPSIS
    Installs all Forensic Suite V2 Windows services in a clean, idempotent way.

.DESCRIPTION
    - Detects active suite root (blue/green via symlink)
    - Installs btc_indexer, eth_indexer, tron_indexer, dashboard_service
    - Ensures proper service recovery settings
    - Safe to run repeatedly
#>

Write-Host "=== Forensic Suite V2 - Service Installer ===" -ForegroundColor Cyan

$SuiteRoot = "C:\forensic_suite_v2"
if (-not (Test-Path $SuiteRoot)) {
    throw "Suite root not found at $SuiteRoot"
}

$ResolvedRoot = (Get-Item $SuiteRoot).Target
if (-not $ResolvedRoot) {
    $ResolvedRoot = $SuiteRoot
}

Write-Host "Active suite root: $ResolvedRoot" -ForegroundColor Yellow

$PythonExe = Join-Path $ResolvedRoot "venv\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    throw "Python executable not found at $PythonExe"
}

$services = @(
    @{
        Name = "btc_indexer"
        Script = "forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"
    },
    @{
        Name = "eth_indexer"
        Script = "forensic_suite_v2\eth_indexer\services\run_eth_indexer_v2.py"
    },
    @{
        Name = "tron_indexer"
        Script = "forensic_suite_v2\tron_indexer\services\run_tron_indexer_v2.py"
    },
    @{
        Name = "dashboard_service"
        Script = "forensic_suite_v2\gui\app.py"
    }
)

foreach ($svc in $services) {

    $svcName = $svc.Name
    $scriptPath = Join-Path $ResolvedRoot $svc.Script

    if (-not (Test-Path $scriptPath)) {
        Write-Warning "Skipping $svcName — script not found: $scriptPath"
        continue
    }

    Write-Host "`n--- Installing $svcName ---" -ForegroundColor Green

    if (Get-Service $svcName -ErrorAction SilentlyContinue) {
        Stop-Service $svcName -Force -ErrorAction SilentlyContinue
        sc.exe delete $svcName | Out-Null
        Start-Sleep -Seconds 1
    }

    $binPath = "`"$PythonExe`" `"$scriptPath`""
    sc.exe create $svcName binPath= $binPath start= auto DisplayName= $svcName | Out-Null
    sc.exe config $svcName obj= LocalSystem | Out-Null
    sc.exe failure $svcName reset= 0 actions= restart/5000 | Out-Null

    Start-Service $svcName -ErrorAction SilentlyContinue
}

Write-Host "`n=== Service installation complete ===" -ForegroundColor Cyan
