<#
.SYNOPSIS
    Deploys BTC, TRON, and ETH ingestion configs to their respective hosts.

.DESCRIPTION
    This script wraps Deploy-ChainHost.ps1 and performs a coordinated
    multi-host ingestion deployment:
        BTC  → 192.168.0.172
        TRON → 192.168.0.165
        ETH  → 192.168.0.199

.EXAMPLE
    .\Deploy-Cluster.ps1
#>

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployChain = Join-Path $ScriptRoot "Deploy-ChainHost.ps1"

$map = @{
    btc  = "192.168.0.172"
    tron = "192.168.0.165"
    eth  = "192.168.0.199"
}

Write-Host "=== Deploying Full Ingestion Cluster ===" -ForegroundColor Cyan

foreach ($chain in $map.Keys) {
    $host = $map[$chain]
    Write-Host ""
    Write-Host ">>> Deploying $chain to $host" -ForegroundColor Yellow

    & $DeployChain -ChainProfile $chain -TargetHost $host

    Write-Host ">>> Completed: $chain → $host" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Cluster Deployment Complete ===" -ForegroundColor Green
