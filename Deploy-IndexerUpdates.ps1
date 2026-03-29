# ---------------------------------------------------------
# Deploy-IndexerUpdates.ps1 - Multi-File Support
# ---------------------------------------------------------

# Define nodes and the specific list of files to sync for each
$Nodes = @(
    @{
        IP    = "192.168.0.165";
        Chain = "eth";
        Files = @(
            "core\indexer_engine.py",
            "eth_indexer\services\block_scanner.py"
            "eth_indexer\services\db_writer.py",
            "eth_indexer\services\receipt_worker.py"
            # Add future ETH files here (e.g., "eth_indexer\services\receipt_worker.py")
        )
    },
    @{
        IP    = "192.168.0.172";
        Chain = "tron";
        Files = @(
            "core\indexer_engine.py",
            "tron_indexer\services\block_scanner",
            "tron_indexer\services\db_writer.py",
            "tron_indexer\services\receipt_worker.py"
        )
    },
    @{
        IP    = "192.168.0.199";
        Chain = "btc";
        Files = @(
            "core\indexer_engine.py",
            "btc_indexer\services\block_scanner.py",
            "btc_indexer\services\db_writer.py",
            "btc_indexer\services\receipt_worker.py"
        )
    }
)

$DBHost     = "192.168.0.28"
$PSQL       = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
$RemoteRoot = "C:\forensic_suite_v2_green"
$LocalRoot  = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\forensic_suite_v2"
$SSHKey     = "C:\Users\louis\.ssh\id_ed25519"

# Set environment variable for password to avoid interactive prompt
$env:PGPASSWORD = "Str0ngPassw0rd2025"

function Get-TS { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

Write-Host "=== Deployment Start: $(Get-TS) ===" -ForegroundColor Cyan

# 1. DB Server Timestamp & Partition Validation
Write-Host "[(Get-TS)] Validating partitions and checking DB time on $DBHost..." -ForegroundColor Cyan
$ValidationSQL = "SELECT NOW() as db_time; SELECT relname FROM pg_class JOIN pg_inherits ON pg_class.oid = pg_inherits.inhparent WHERE relname IN ('erc20_transfers', 'trc20_transfers', 'address_tx_index') GROUP BY relname;"
& $PSQL -h $DBHost -U postgres -d forensic -c "$ValidationSQL"

# 2. Reset Global Checkpoints (Force engine to use YAML start_block)
Write-Host "[(Get-TS)] Clearing index_checkpoint table..." -ForegroundColor Yellow
$ResetSQL = "DELETE FROM index_checkpoint WHERE chain IN ('eth', 'tron', 'btc');"
& $PSQL -h $DBHost -U postgres -d forensic -c "$ResetSQL"

# 3. Node Deployment Loop
foreach ($Node in $Nodes) {
    $Svc = "$($Node.Chain)_indexer"
    $Target = "forensicuser@$($Node.IP)"
    Write-Host "`n[(Get-TS)] NODE: $($Node.IP) ($($Node.Chain))" -ForegroundColor Cyan

    # A. Stop Service (Prevents WinError 5 Access Denied)
    Write-Host "[(Get-TS)] Stopping $Svc..." -ForegroundColor Yellow
    ssh -i $SSHKey $Target "powershell -Command C:\tools\nssm\nssm.exe stop $Svc"

    # B. Wipe Logs for fresh testing
    Write-Host "[(Get-TS)] Wiping logs for $Svc..." -ForegroundColor Gray
    $LogDir = "C:\forensic_suite_logs"
    ssh -i $SSHKey $Target "powershell -Command `"Clear-Content $LogDir\$Svc.err.log, $LogDir\$Svc.out.log -ErrorAction SilentlyContinue`""

    # C. Remove Local State File
    $State = "C:\forensic_state\$($Node.Chain)\$($Node.Chain)_checkpoint.json"
    Write-Host "[(Get-TS)] Deleting local checkpoint mirror: $State" -ForegroundColor Magenta
    ssh -i $SSHKey $Target "powershell -Command Remove-Item $State -Force -ErrorAction SilentlyContinue"

    # D. Transfer Multiple Files
    foreach ($RelativePath in $Node.Files) {
        $LocalPath = Join-Path $LocalRoot $RelativePath

        # Define the two remote destinations per file
        $RemotePaths = @(
            "$RemoteRoot\forensic_suite_v2\$RelativePath",
            "$RemoteRoot\python\Lib\site-packages\forensic_suite_v2\$RelativePath"
        )

        foreach ($Dest in $RemotePaths) {
            Write-Host "[(Get-TS)] Copying $RelativePath to $Dest..." -ForegroundColor Gray
            scp -i $SSHKey $LocalPath "$($Target):$Dest"
        }
    }

    # E. Start Service
    Write-Host "[(Get-TS)] Starting $Svc..." -ForegroundColor Green
    ssh -i $SSHKey $Target "powershell -Command C:\tools\nssm\nssm.exe start $Svc"
}

# Clear password from memory
$env:PGPASSWORD = $null
Write-Host "`n=== Deployment Finished: $(Get-TS) ===" -ForegroundColor Cyan
