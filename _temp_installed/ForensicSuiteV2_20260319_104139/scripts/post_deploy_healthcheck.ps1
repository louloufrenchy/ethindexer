# =====================================================================
# Forensic Suite V2 — Post Deployment Health Check
# =====================================================================

param(
    [string]$SuiteRoot = "C:\forensic_suite_v2",
    [string]$Python = "C:\Program Files\Python314\python.exe"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Forensic Suite V2 Post-Deployment Health Check ===" -ForegroundColor Cyan

# 1. Schema validation
Write-Host "[1/4] Running schema validator..." -ForegroundColor Cyan

$btc = Join-Path $SuiteRoot "forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"
$validator = & cmd.exe /c "set PYTHONPATH=$SuiteRoot && `"$Python`" `"$btc`" --validate-only"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Schema validation failed." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Schema validation passed." -ForegroundColor Green

# 2. Check service status
Write-Host "[2/4] Checking Windows services..." -ForegroundColor Cyan

$services = @(
    "Forensic-BTC",
    "Forensic-ETH",
    "Forensic-TRON"
)

foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) {
        Write-Host "[FAIL] Missing service: $svc" -ForegroundColor Red
        exit 2
    }
    Write-Host "[OK] $svc : $($s.Status)" -ForegroundColor Green
}

# 3. Check ingestion lag
Write-Host "[3/4] Checking ingestion lag..." -ForegroundColor Cyan

$query = "SELECT chain, lag FROM indexer_metrics ORDER BY ts DESC LIMIT 3;"
$lag = & psql -U postgres -d forensic -c $query

Write-Host $lag

# 4. Final OK
Write-Host "[SUCCESS] Post-deployment health check complete." -ForegroundColor Green
exit 0