if ($PSVersionTable.PSVersion.Major -ge 6) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit
}

<#
 Forensic Suite v2 – ETH Indexer Launcher
#>

$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Base

Write-Host "=== Starting ETH Indexer ===" -ForegroundColor Cyan
Write-Host "Base directory: $Root" -ForegroundColor DarkGray

$VenvActivate = Join-Path $Root "venv\Scripts\Activate.ps1"
$PythonExe    = Join-Path $Root "venv\Scripts\python.exe"

if (-not (Test-Path $VenvActivate)) { Write-Host "[ERROR] venv not found." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $PythonExe))    { Write-Host "[ERROR] python.exe missing." -ForegroundColor Red; exit 1 }

. $VenvActivate

$LogDir  = Join-Path $Root "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "eth_indexer.log"

Write-Host "Logging to: $LogFile" -ForegroundColor DarkGray

$IndexerCommand = @("-m", "forensic_suite_v2.indexers.eth_indexer")

Start-Process -FilePath $PythonExe `
    -ArgumentList $IndexerCommand `
    -RedirectStandardOutput $LogFile `
    -RedirectStandardError ($LogFile + ".err") `
    -WindowStyle Minimized

Write-Host "ETH indexer started." -ForegroundColor Green
