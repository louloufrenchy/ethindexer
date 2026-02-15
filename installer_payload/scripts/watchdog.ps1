<#
 Forensic Suite v2 – Indexer Watchdog
 Restarts BTC/ETH/TRON indexers if logs stop updating
#>

$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Base
$RunIndexer = Join-Path $Base "run_indexer.ps1"

$Chains = @("btc","eth","tron")

while ($true) {
    foreach ($chain in $Chains) {

        $LogFile = Join-Path (Join-Path $Root "logs") ("{0}_indexer.log" -f $chain)

        $needsRestart = $false

        if (-not (Test-Path $LogFile)) {
            $needsRestart = $true
        }
        else {
            $age = (Get-Item $LogFile).LastWriteTime
            if ((Get-Date) - $age -gt [TimeSpan]::FromMinutes(5)) {
                $needsRestart = $true
            }
        }

        if ($needsRestart) {
            Write-Host "[WATCHDOG] Restarting $chain indexer..." -ForegroundColor Yellow
            & $RunIndexer -chain $chain
        }
    }

    Start-Sleep -Seconds 60
}
