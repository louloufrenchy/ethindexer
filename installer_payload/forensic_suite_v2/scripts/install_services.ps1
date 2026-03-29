<#
.SYNOPSIS
    Installs Forensic Suite V2 Windows services using NSSM, based on enabled chains in indexer.yaml.

.DESCRIPTION
    - Detects active suite root (blue/green aware)
    - Reads forensic_suite_v2\config\indexer.yaml
    - Installs ONLY enabled chain services (btc / eth / tron)
    - Always installs forensic_orchestrator
    - Loads secrets from C:\forensic_secrets\.env into each service environment
    - Safe to run repeatedly
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n=== Installing Forensic Suite services (NSSM, YAML-aware) ===" -ForegroundColor Cyan

function Get-EnvFileEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw ".env file not found: $Path"
    }

    $entries = @()

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '=') { continue }

        $name, $value = $trimmed.Split('=', 2)
        $name = $name.Trim()
        $value = $value.Trim()

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $entries += ('{0}={1}' -f $name, $value)
        }
    }

    return $entries
}

function Test-ChainEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlText,

        [Parameter(Mandatory = $true)]
        [ValidateSet('btc','eth','tron')]
        [string]$Chain
    )

    return ($YamlText -match ("(?ms)^" + [regex]::Escape($Chain) + ":\r?\n.*?^\s*enabled:\s*true\s*$"))
}

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot  = Split-Path -Parent $ScriptRoot
$ResolvedRoot = Split-Path -Parent $PackageRoot

Write-Host "ScriptRoot   : $ScriptRoot"   -ForegroundColor DarkGray
Write-Host "PackageRoot  : $PackageRoot"  -ForegroundColor DarkGray
Write-Host "ResolvedRoot : $ResolvedRoot" -ForegroundColor DarkGray

$LogsRoot    = "C:\forensic_suite_logs"
$StateRoot   = "C:\forensic_state"
$SecretsRoot = "C:\forensic_secrets"
$EnvFile     = Join-Path $SecretsRoot ".env"
$ConfigPath  = Join-Path $ResolvedRoot "forensic_suite_v2\config\indexer.yaml"

$NssmExe   = Join-Path $ResolvedRoot "tools\nssm\nssm.exe"
$PyExeSlot = Join-Path $ResolvedRoot "python\python.exe"

$VenvRoot   = Join-Path $ResolvedRoot "venv"
$VenvPython = Join-Path $VenvRoot "Scripts\python.exe"

New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "btc") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "eth") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StateRoot "tron") -Force | Out-Null
New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $SecretsRoot -Force | Out-Null

if (Test-Path $VenvPython) {
    $PythonExe = $VenvPython
    Write-Host "[OK] Using slot-local venv Python: $PythonExe" -ForegroundColor Green
}
elseif (Test-Path $PyExeSlot) {
    $PythonExe = $PyExeSlot
    Write-Host "[OK] Using slot-local Python runtime: $PythonExe" -ForegroundColor Green
}
else {
    throw "No Python runtime found. Expected either venv at '$VenvPython' or slot runtime at '$PyExeSlot'."
}

if (-not (Test-Path $NssmExe)) {
    throw "NSSM executable not found at $NssmExe"
}

if (-not (Test-Path $ConfigPath)) {
    throw "indexer.yaml not found at $ConfigPath"
}

$EnvEntries = Get-EnvFileEntries -Path $EnvFile
$YamlText   = Get-Content $ConfigPath -Raw

$btcEnabled  = Test-ChainEnabled -YamlText $YamlText -Chain 'btc'
$ethEnabled  = Test-ChainEnabled -YamlText $YamlText -Chain 'eth'
$tronEnabled = Test-ChainEnabled -YamlText $YamlText -Chain 'tron'

Write-Host "Using NSSM   : $NssmExe"    -ForegroundColor Yellow
Write-Host "Logs root    : $LogsRoot"   -ForegroundColor Yellow
Write-Host "State root   : $StateRoot"  -ForegroundColor Yellow
Write-Host "Secrets file : $EnvFile"    -ForegroundColor Yellow
Write-Host "Env entries  : $($EnvEntries.Count)" -ForegroundColor Yellow
Write-Host "Config file  : $ConfigPath" -ForegroundColor Yellow
Write-Host ("Enabled      : btc={0} eth={1} tron={2}" -f $btcEnabled, $ethEnabled, $tronEnabled) -ForegroundColor Yellow

$services = @()

if ($btcEnabled) {
    $services += @{
        Name   = "btc_indexer"
        Script = "forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"
        Type   = "python"
    }
}

if ($ethEnabled) {
    $services += @{
        Name   = "eth_indexer"
        Script = "forensic_suite_v2\eth_indexer\services\run_eth_indexer_v2.py"
        Type   = "python"
    }
}

if ($tronEnabled) {
    $services += @{
        Name   = "tron_indexer"
        Script = "forensic_suite_v2\tron_indexer\services\run_tron_indexer_v2.py"
        Type   = "python"
    }
}

$services += @{
    Name   = "forensic_orchestrator"
    Script = "forensic_suite_v2\scripts\windows_orchestrator_service.ps1"
    Type   = "powershell"
}

$allChainServices = @('btc_indexer', 'eth_indexer', 'tron_indexer')
$enabledNames = @($services | ForEach-Object { $_.Name })

foreach ($svcName in $allChainServices) {
    if ($enabledNames -contains $svcName) { continue }

    $existing = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host ("`n--- Removing disabled service {0} ---" -f $svcName) -ForegroundColor Yellow

        try {
            Stop-Service $svcName -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        & sc.exe delete $svcName | Out-Null
        Start-Sleep -Seconds 2
    }
}

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
        $appDirectory = Join-Path $ResolvedRoot "forensic_suite_v2"
        $pythonPathRoot = $ResolvedRoot
    }
    else {
        & $NssmExe install $svcName $PythonExe | Out-Null
        & $NssmExe set $svcName AppParameters ('"{0}"' -f $scriptPath) | Out-Null
        $appDirectory = $ResolvedRoot
        $pythonPathRoot = $ResolvedRoot
    }

    $AppEnv = @(
        "PYTHONPATH=$pythonPathRoot"
        "PYTHONUNBUFFERED=1"
        "PYTHONIOENCODING=utf-8"
        "VIRTUAL_ENV=$VenvRoot"
    ) + $EnvEntries

    & $NssmExe set $svcName AppDirectory $appDirectory | Out-Null
    & $NssmExe set $svcName Start SERVICE_AUTO_START | Out-Null
    & $NssmExe set $svcName AppExit Default Restart | Out-Null
    & $NssmExe set $svcName AppEnvironment "" | Out-Null
    & $NssmExe set $svcName AppEnvironmentExtra @AppEnv | Out-Null
    & $NssmExe set $svcName AppStdout (Join-Path $LogsRoot "$svcName.out.log") | Out-Null
    & $NssmExe set $svcName AppStderr (Join-Path $LogsRoot "$svcName.err.log") | Out-Null

    Write-Host ("AppDirectory for {0}: {1}" -f $svcName, $appDirectory) -ForegroundColor DarkGray

    $failureResult = & sc.exe failure $svcName reset= 0 actions= restart/5000
    if ($LASTEXITCODE -ne 0) {
        Write-Warning ("sc failure failed for {0}: {1}" -f $svcName, ($failureResult -join ' '))
    }

    Start-Sleep -Seconds 1

    try {
        Start-Service $svcName -ErrorAction Stop
        Start-Sleep -Seconds 2

        $started = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($started -and ($started.Status -eq 'Running' -or $started.Status -eq 'StartPending')) {
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
