function Show-Menu {
    Clear-Host
    Write-Host "=== ForensicSuiteV2 Operator Console ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) BTC dashboard"
    Write-Host "2) ETH dashboard"
    Write-Host "3) TRON dashboard"
    Write-Host "4) Multi-chain dashboard"
    Write-Host "5) Validate host"
    Write-Host "6) Run DB migrations"
    Write-Host "Q) Quit"
    Write-Host ""
}

$base = "C:\Program Files\ForensicSuiteV2"

while ($true) {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice.ToUpper()) {
        "1" {
            & powershell -NoExit -File (Join-Path $base "btc_dashboard.ps1")
        }
        "2" {
            & powershell -NoExit -File (Join-Path $base "eth_dashboard.ps1")
        }
        "3" {
            & powershell -NoExit -File (Join-Path $base "tron_dashboard.ps1")
        }
        "4" {
            & powershell -NoExit -File (Join-Path $base "multi_chain_dashboard.ps1")
        }
        "5" {
            & powershell -NoExit -File (Join-Path $base "validate_host.ps1")
        }
        "6" {
            & powershell -NoExit -File (Join-Path $base "run_migrations.ps1")
        }
        "Q" {
            break
        }
        default {
            Write-Host "Invalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
