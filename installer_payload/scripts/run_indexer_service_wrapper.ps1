<#
 Forensic Suite v2 – Indexer Service Wrapper (NSSM)
 Installs or removes BTC/ETH/TRON indexers as Windows services
#>

param(
    [ValidateSet("install","remove")]
    [string]$Action = "install"
)

$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Base
$Nssm = Join-Path $Root "tools\nssm.exe"

if (-not (Test-Path $Nssm)) {
    Write-Host "[ERROR] NSSM not found at $Nssm" -ForegroundColor Red
    exit 1
}

$Services = @(
    @{ Name = "ForensicSuiteV2_BTC";  Script = Join-Path $Base "run_btc_indexer.ps1" },
    @{ Name = "ForensicSuiteV2_ETH";  Script = Join-Path $Base "run_eth_indexer.ps1" },
    @{ Name = "ForensicSuiteV2_TRON"; Script = Join-Path $Base "run_tron_indexer.ps1" }
)

foreach ($svc in $Services) {

    if ($Action -eq "install") {

        if (-not (Test-Path $svc.Script)) {
            Write-Host "[WARN] Missing script for $($svc.Name)" -ForegroundColor Yellow
            continue
        }

        & $Nssm install $svc.Name "powershell.exe" `
            " -ExecutionPolicy Bypass -File `"$($svc.Script)`""

        & $Nssm set $svc.Name Start SERVICE_AUTO_START
        & $Nssm set $svc.Name AppDirectory $Root

        Write-Host "Installed service: $($svc.Name)" -ForegroundColor Green
    }

    elseif ($Action -eq "remove") {
        & $Nssm remove $svc.Name confirm
        Write-Host "Removed service: $($svc.Name)" -ForegroundColor Yellow
    }
}
