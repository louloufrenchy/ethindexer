if ($PSVersionTable.PSVersion.Major -ge 6) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit
}
<#
 Forensic Suite v2 – Run All Indexers
#>

$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Base

Write-Host "=== Starting ALL Indexers ===" -ForegroundColor Cyan

$Scripts = @(
    "run_btc_indexer.ps1",
    "run_eth_indexer.ps1",
    "run_tron_indexer.ps1"
)

foreach ($s in $Scripts) {
    $Path = Join-Path $Base $s
    if (Test-Path $Path) {
        Write-Host "Launching $s..." -ForegroundColor Cyan
        Start-Process "powershell.exe" `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$Path`"" `
            -WindowStyle Minimized
    } else {
        Write-Host "Missing: $Path" -ForegroundColor Yellow
    }
}

Write-Host "All indexers launched." -ForegroundColor Green
