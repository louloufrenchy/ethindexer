Write-Host "=== ForensicSuiteV2 Host Validation ===" -ForegroundColor Cyan

$pgBin = "C:\Program Files\PostgreSQL\18\bin"
$psql  = Join-Path $pgBin "psql.exe"

$env:PGPASSWORD = "Str0ngPassw0rd2025"

# 1. Check Postgres connectivity
Write-Host "`n[1/4] Checking PostgreSQL connectivity..." -ForegroundColor Yellow
try {
    & $psql -U postgres -d postgres -c "SELECT version();" | Out-Null
    Write-Host "PostgreSQL reachable as postgres." -ForegroundColor Green
} catch {
    Write-Host "Failed to connect to PostgreSQL as postgres." -ForegroundColor Red
}

# 2. Check forensic DB existence
Write-Host "`n[2/4] Checking forensic database..." -ForegroundColor Yellow
$dbs = & $psql -U postgres -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname = 'forensic';"
if ($dbs.Trim() -eq "forensic") {
    Write-Host "forensic database exists." -ForegroundColor Green
} else {
    Write-Host "forensic database is missing." -ForegroundColor Red
}

# 3. Check core tables
Write-Host "`n[3/4] Checking core tables in forensic..." -ForegroundColor Yellow
$coreTables = @(
    "btc_blocks",
    "btc_index_checkpoint",
    "eth_blocks",
    "eth_index_checkpoint",
    "tron_block_hashes",
    "index_checkpoint_tron",
    "ingestion_metrics"
)

foreach ($t in $coreTables) {
    $exists = & $psql -U postgres -d forensic -t -A -c "SELECT to_regclass('$t');"
    if ($exists.Trim() -eq $t) {
        Write-Host ("Table {0} exists." -f $t) -ForegroundColor Green
    } else {
        Write-Host ("Table {0} is MISSING." -f $t) -ForegroundColor Red
    }
}

# 4. Check venv + wheel
Write-Host "`n[4/4] Checking Python environment..." -ForegroundColor Yellow
$venvPath = "C:\Program Files\ForensicSuiteV2\venv\Scripts\python.exe"
if (Test-Path $venvPath) {
    Write-Host "Python venv found." -ForegroundColor Green
    & "C:\Program Files\ForensicSuiteV2\venv\Scripts\pip.exe" list | Select-String "forensic-suite-v2" | ForEach-Object {
        Write-Host "forensic-suite-v2 package installed: $_" -ForegroundColor Green
    }
} else {
    Write-Host "Python venv not found at $venvPath" -ForegroundColor Red
}

Write-Host "`nValidation complete." -ForegroundColor Cyan
