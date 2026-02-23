<#
    eth_dashboard.ps1
    - Simple ETH progress dashboard
    - Mirrors tron_dashboard.ps1 / btc_dashboard.ps1 style
    - Polls index_checkpoint for ETH and prints progress
#>

param(
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$PgDb = "forensic",
    [string]$PgUser = "postgres",
    [int]$RefreshSeconds = 5
)

Set-Location -Path $PSScriptRoot

Write-Host "=== ETH Dashboard ===" -ForegroundColor Cyan
Write-Host "DB: $PgUser@$PgHost:$PgPort/$PgDb" -ForegroundColor DarkCyan
Write-Host ""

$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

if (-not (Test-Path $psql)) {
    Write-Host "[FAIL] psql not found at $psql" -ForegroundColor Red
    exit 1
}

while ($true) {
    Clear-Host
    Write-Host "=== ETH Dashboard (refresh every $RefreshSeconds s) ===" -ForegroundColor Cyan
    Write-Host ""

    $query = @"
SELECT
    chain,
    last_block,
    last_updated_at
FROM index_checkpoint
WHERE chain = 'ETH'
ORDER BY last_updated_at DESC
LIMIT 1;
"@

    & $psql -h $PgHost -p $PgPort -U $PgUser -d $PgDb -c $query

    Write-Host ""
    Write-Host "Press Ctrl+C to exit." -ForegroundColor DarkGray
    Start-Sleep -Seconds $RefreshSeconds
}
