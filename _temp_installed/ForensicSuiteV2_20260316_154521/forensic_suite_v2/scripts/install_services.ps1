<#
.SYNOPSIS
    Installs all Forensic Suite V2 Windows services using NSSM.

.DESCRIPTION
    - Detects active suite root
    - Installs btc_indexer, eth_indexer, tron_indexer, forensic_orchestrator
    - Uses NSSM so normal Python/PowerShell scripts can run reliably as services
    - Creates runtime state and log directories
    - Prefers slot-local venv Python
    - Safe to run repeatedly
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n=== Installing Forensic Suite services (NSSM) ===" -ForegroundColor Cyan

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot  = Split-Path -Parent $ScriptRoot
$ResolvedRoot = Split-Path -Parent $PackageRoot

$LogsRoot        = "C:\forensic_suite_logs"
$StateRoot       = "C:\forensic_state"
$NssmStableDir   = "F:\tools\nssm"
$NssmExe         = Join-Path $NssmStableDir "nssm.exe"
$VenvRoot        = Join-Path $ResolvedRoot "venv"
$VenvPython      = Join-Path $VenvRoot "Scripts\python.exe"

$PythonCandidates = @(
    $VenvPython,
    "C:\Program Files\Python314\python.exe",
    "C:\Program Files\Python313\python.exe",
    "C:\Program Files\Python312\python.exe",
    "C:\Program Files\Python311\python.exe",
    "python.exe"
)

# ---------------------------------------------------------------------
# Ensure runtime directories
# ---------------------------------------------------------------------
New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "btc") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "eth") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "tron") -Force | Out-Null
New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

# ---------------------------------------------------------------------
# Resolve Python
# ---------------------------------------------------------------------
$PythonExe = $null
foreach ($candidate in $PythonCandidates) {
    if ($candidate -eq "python.exe") {
        $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $PythonExe = $cmd.Source
            break
        }
    }
    elseif (Test-Path $candidate) {
        $PythonExe = $candidate
        break
    }
}

if (-not $PythonExe) {
    throw "Python executable not found."
}

# ---------------------------------------------------------------------
# Validate NSSM
# ---------------------------------------------------------------------
if (-not (Test-Path $NssmExe)) {
    throw "NSSM executable not found at $NssmExe"
}

if ($PythonExe -eq $VenvPython) {
    Write-Host "[OK] Using slot-local venv Python: $PythonExe" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Slot-local venv Python not found. Falling back to: $PythonExe" -ForegroundColor Yellow
}

Write-Host "Using NSSM  : $NssmExe" -ForegroundColor Yellow
Write-Host "Resolved root: $ResolvedRoot" -ForegroundColor Yellow
Write-Host "Logs root   : $LogsRoot" -ForegroundColor Yellow
Write-Host "State root  : $StateRoot" -ForegroundColor Yellow

$services = @(
    @{
        Name   = "btc_indexer"
        Script = "forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"
        Type   = "python"
    },
    @{
        Name   = "eth_indexer"
        Script = "forensic_suite_v2\eth_indexer\services\run_eth_indexer_v2.py"
        Type   = "python"
    },
    @{
        Name   = "tron_indexer"
        Script = "forensic_suite_v2\tron_indexer\services\run_tron_indexer_v2.py"
        Type   = "python"
    },
    @{
        Name   = "forensic_orchestrator"
        Script = "forensic_suite_v2\scripts\windows_orchestrator_service.ps1"
        Type   = "powershell"
    }
)

foreach ($svc in $services) {
    $svcName    = $svc.Name
    $scriptPath = Join-Path $ResolvedRoot $svc.Script

    if (-not (Test-Path $scriptPath)) {
        Write-Warning ("Skipping {0} - script not found: {1}" -f $svcName, $scriptPath)
        continue
    }

    Write-Host ("`n--- Installing {0} ---" -f $svcName) -ForegroundColor Green

    $existing = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            Stop-Service $svcName -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        & sc.exe delete $svcName | Out-Null
        Start-Sleep -Seconds 2
    }

    if ($svc.Type -eq "powershell") {
        & $NssmExe install $svcName "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null
        & $NssmExe set $svcName AppParameters ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath) | Out-Null
    }
    else {
        & $NssmExe install $svcName $PythonExe | Out-Null
        & $NssmExe set $svcName AppParameters ('"{0}"' -f $scriptPath) | Out-Null
    }

    & $NssmExe set $svcName AppDirectory $ResolvedRoot | Out-Null
    & $NssmExe set $svcName Start SERVICE_AUTO_START | Out-Null
    & $NssmExe set $svcName AppExit Default Restart | Out-Null
    & $NssmExe set $svcName AppEnvironmentExtra `
        "PYTHONPATH=$ResolvedRoot" `
        "PYTHONUNBUFFERED=1" `
        "VIRTUAL_ENV=$VenvRoot" | Out-Null
    & $NssmExe set $svcName AppStdout (Join-Path $LogsRoot "$svcName.out.log") | Out-Null
    & $NssmExe set $svcName AppStderr (Join-Path $LogsRoot "$svcName.err.log") | Out-Null

    $failureResult = & sc.exe failure $svcName reset= 0 actions= restart/5000
    if ($LASTEXITCODE -ne 0) {
        Write-Warning ("sc failure failed for {0}: {1}" -f $svcName, ($failureResult -join ' '))
    }

    Start-Sleep -Seconds 1

    try {
        Start-Service $svcName -ErrorAction Stop
        Start-Sleep -Seconds 2

        $started = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($started -and $started.Status -eq 'Running') {
            Write-Host ("Started {0}" -f $svcName) -ForegroundColor Cyan
        }
        else {
            Write-Warning ("Installed {0} but it is not running after start attempt." -f $svcName)
        }
    }
    catch {
        Write-Warning ("Installed {0} but could not start it immediately: {1}" -f $svcName, $_.Exception.Message)
    }
}

Write-Host "`n=== Service installation complete ===" -ForegroundColor Cyan
exit 0
