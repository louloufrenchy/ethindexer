# ---------------------------------------------------------
# Test-ForensicIntegrity.ps1 - Dual-Phase Investigation
# ---------------------------------------------------------
$DBHost = "192.168.0.28"
$PSQL = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
$SSHKey = "C:\Users\louis\.ssh\id_ed25519"
$env:PGPASSWORD = "Str0ngPassw0rd2025"

function Get-TS { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

function Run-DBAudit {
    param($Title)
    Write-Host "`n[(Get-TS)] >>> DATABASE REPORT: $Title <<<" -ForegroundColor Cyan
    $Queries = @(
        "SELECT chain, last_block, updated_at FROM index_checkpoint ORDER BY chain;"
        "SELECT count(*) as eth_blocks FROM eth_blocks;"
        "SELECT count(*) as tron_blocks FROM tron_blocks;"
        "SELECT count(*) as btc_blocks FROM btc_blocks;"
        "SELECT count(*) as erc20_transfers FROM erc20_transfers;"
        "SELECT count(*) as trc20_transfers FROM trc20_transfers;"
        "SELECT count(*) as total_address_tx_index FROM address_tx_index;"
    )
    foreach ($Q in $Queries) {
        & $PSQL -h $DBHost -U postgres -d forensic -c "$Q"
    }
}

Write-Host "=== Forensic Integrity Test Start: $(Get-TS) ===" -ForegroundColor Cyan

# 1. Restart Services
$Nodes = @(
    @{ IP = "192.168.0.165"; Svc = "eth_indexer"; Chain = "ETH" },
    @{ IP = "192.168.0.172"; Svc = "tron_indexer"; Chain = "TRON" },
    @{ IP = "192.168.0.199"; Svc = "btc_indexer"; Chain = "BTC" }
)

foreach ($Node in $Nodes) {
    Write-Host "[(Get-TS)] Restarting $($Node.Svc) on $($Node.IP)..." -ForegroundColor Yellow
    ssh -i $SSHKey forensicuser@$($Node.IP) "powershell -Command C:\tools\nssm\nssm.exe restart $($Node.Svc)"
}

# PHASE 1: Quick Check (90 Seconds)
Write-Host "`n[(Get-TS)] PHASE 1: Waiting 90 seconds for initial ingestion..." -ForegroundColor Gray
Start-Sleep -Seconds 90

Run-DBAudit -Title "Initial 90s Check"

Write-Host "`n[(Get-TS)] >>> PHASE 1 REMOTE LOGS (Last 10) <<<" -ForegroundColor Cyan
foreach ($Node in $Nodes) {
    Write-Host "--- $($Node.Chain) ($($Node.IP)) ---" -ForegroundColor Yellow
    ssh -i $SSHKey forensicuser@$($Node.IP) "powershell -Command `"Get-Content C:\forensic_suite_logs\$($Node.Svc).err.log -Tail 10 -ErrorAction SilentlyContinue`""
}

# PHASE 2: Deep Dive (240 Seconds)
Write-Host "`n[(Get-TS)] PHASE 2: Waiting additional 240 seconds for stability check..." -ForegroundColor Gray
Start-Sleep -Seconds 240

Run-DBAudit -Title "Final 240s Stability Check"

Write-Host "`n[(Get-TS)] >>> PHASE 2 DEEP LOG DUMP (Last 100) <<<" -ForegroundColor Cyan
foreach ($Node in $Nodes) {
    Write-Host "--- $($Node.Chain) ($($Node.IP)) ---" -ForegroundColor Yellow
    ssh -i $SSHKey forensicuser@$($Node.IP) "powershell -Command `"Get-Content C:\forensic_suite_logs\$($Node.Svc).err.log -Tail 100 -ErrorAction SilentlyContinue`""
}

$env:PGPASSWORD = $null
Write-Host "`n=== Integrity Test Complete: $(Get-TS) ===" -ForegroundColor Cyan
