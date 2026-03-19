param(
    [Parameter(Mandatory = $true)][string]$Host
)

Write-Host "=== Runtime Prep Healthcheck for $Host ===" -ForegroundColor Cyan

$script = @"
`$ErrorActionPreference = 'Stop'

`$PythonExe = 'C:\Program Files\Python314\python.exe'
`$SuiteRoot = 'C:\forensic_suite_v2'
`$WheelDir  = Join-Path `$SuiteRoot 'wheel'
`$LogsRoot  = 'C:\forensic_suite_logs'

Write-Host "[INFO] Checking Python..." -ForegroundColor Gray
if (-not (Test-Path `$PythonExe)) { throw "Python missing: `$PythonExe" }

Write-Host "[INFO] Checking suite root..." -ForegroundColor Gray
if (-not (Test-Path `$SuiteRoot)) { throw "Suite root missing: `$SuiteRoot" }

Write-Host "[INFO] Checking wheel directory..." -ForegroundColor Gray
if (-not (Test-Path `$WheelDir)) { throw "Wheel directory missing: `$WheelDir" }

`$wheel = Get-ChildItem `$WheelDir -Filter 'forensic_suite_v2-*.whl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not `$wheel) { throw "No forensic_suite_v2 wheel found in `$WheelDir" }

Write-Host "[OK] Wheel: $(`$wheel.FullName)" -ForegroundColor Green

Write-Host "[INFO] Checking services..." -ForegroundColor Gray
`$svc = Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator -ErrorAction SilentlyContinue

if (-not `$svc -or `$svc.Count -lt 4) {
    throw "One or more services are missing."
}

`$bad = `$svc | Where-Object { `$_.Status -ne 'Running' }
if (`$bad) {
    `$names = (`$bad | Select-Object -ExpandProperty Name) -join ', '
    throw "Services not running: `$names"
}

Write-Host "[OK] All services running." -ForegroundColor Green

Write-Host "[INFO] Checking logs root..." -ForegroundColor Gray
if (-not (Test-Path `$LogsRoot)) { throw "Logs root missing: `$LogsRoot" }

Write-Host "[OK] Runtime prep healthcheck passed." -ForegroundColor Green
"@

$result = Invoke-RemotePS -Host $Host -Script $script
$result
