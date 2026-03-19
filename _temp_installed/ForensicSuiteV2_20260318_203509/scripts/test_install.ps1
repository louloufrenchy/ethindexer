# =====================================================================
# TEST INSTALL (V6) - SOURCE HOST MIRROR OF DESTINATION DEPLOYMENT
# =====================================================================
#
# PURPOSE
#   - Mimic a real destination-host deployment on the source host
#   - Stage installer_payload into C:\forensic_suite_v2_green
#   - Ensure Python 3.14 exists
#   - Create slot-local venv
#   - Install requirements + latest wheel
#   - Switch C:\forensic_suite_v2 symlink to GREEN
#   - Install/update services using NSSM
#   - Start services and print diagnostics
#
# RUN AS
#   Elevated PowerShell (Run as Administrator)
#
# NOTES
#   - This script assumes Repo A is on the source host at:
#       F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root
#   - Put nssm.exe in either:
#       F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\tools\nssm.exe
#     or ensure it is already present at:
#       F:\tools\nssm\nssm.exe
#   - Secrets are expected at:
#       F:\forensic_secrets\env.json
# =====================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# REPO A / PAYLOAD / SLOT PATHS
# ---------------------------------------------------------------------
$PrimaryRoot      = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$PayloadRoot      = Join-Path $PrimaryRoot "installer_payload"
$GreenRoot        = "C:\forensic_suite_v2_green"
$RuntimeLink      = "C:\forensic_suite_v2"
$SecretRoot       = "F:\forensic_secrets"
$SecretFile       = Join-Path $SecretRoot "env.json"
$LogsRoot         = "C:\forensic_suite_logs"

# ---------------------------------------------------------------------
# PYTHON 3.14 STANDARD
# ---------------------------------------------------------------------
$Python314        = "C:\Program Files\Python314\python.exe"
$PythonInstaller  = Join-Path $PrimaryRoot "python-3.14.2-amd64.exe"

# ---------------------------------------------------------------------
# NSSM (stable location, outside blue/green slot)
# ---------------------------------------------------------------------
$NssmStableDir    = "F:\tools\nssm"
$NssmExe          = Join-Path $NssmStableDir "nssm.exe"
$NssmRepoSource   = Join-Path $PrimaryRoot "tools\nssm.exe"
$NssmPayloadSource= Join-Path $PayloadRoot "tools\nssm.exe"

# -------------------------------------------------------------------
# Ensure NSSM locally
# -------------------------------------------------------------------
$LocalNssmSource = Join-Path $PSScriptRoot "..\third_party\nssm\nssm.exe"
$LocalNssmSource = (Resolve-Path $LocalNssmSource).Path
$NssmTargetDir   = "F:\tools\nssm"
$NssmTargetExe   = Join-Path $NssmTargetDir "nssm.exe"

Write-Host "`n=== Ensuring NSSM ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $NssmTargetDir -Force | Out-Null

if (-not (Test-Path $NssmTargetExe)) {
    if (-not (Test-Path $LocalNssmSource)) {
        throw "NSSM source not found at $LocalNssmSource"
    }

    Copy-Item $LocalNssmSource $NssmTargetExe -Force
    Write-Host "[OK] NSSM copied to $NssmTargetExe" -ForegroundColor Green
}
else {
    Write-Host "[OK] NSSM already installed: $NssmTargetExe" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# SERVICE DEFINITIONS
# ---------------------------------------------------------------------
$Services = @(
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

# ---------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------
function Write-Phase {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Assert-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated PowerShell session."
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-ServicesPipeTimeout {
    Write-Phase "Ensuring ServicesPipeTimeout"
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
    New-ItemProperty -Path $regPath -Name "ServicesPipeTimeout" -PropertyType DWord -Value 120000 -Force | Out-Null
    Write-Host "[OK] ServicesPipeTimeout set to 120000 ms" -ForegroundColor Green
}

function Ensure-Python314 {
    Write-Phase "Ensuring Python 3.14"

    if (Test-Path $Python314) {
        Write-Host "[OK] Python 3.14 found at $Python314" -ForegroundColor Green
        return
    }

    if (-not (Test-Path $PythonInstaller)) {
        throw "Python 3.14 installer not found at $PythonInstaller"
    }

    Write-Host "Installing Python 3.14 silently..." -ForegroundColor Yellow

    $args = @(
        "/quiet",
        "InstallAllUsers=1",
        "TargetDir=`"C:\Program Files\Python314`"",
        "Include_pip=1",
        "Include_test=0",
        "PrependPath=0"
    )

    $proc = Start-Process -FilePath $PythonInstaller -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Python installer exited with code $($proc.ExitCode)"
    }

    if (-not (Test-Path $Python314)) {
        throw "Python 3.14 install completed but $Python314 was not found."
    }

    Write-Host "[OK] Python 3.14 installed at $Python314" -ForegroundColor Green
}

function Ensure-NSSM {

    Write-Phase "Ensuring NSSM"

    $NssmStableDir     = "F:\tools\nssm"
    $NssmExe           = Join-Path $NssmStableDir "nssm.exe"

    $ThirdPartySource  = Join-Path $PrimaryRoot "third_party\nssm\nssm.exe"
    $RepoSource        = Join-Path $PrimaryRoot "tools\nssm.exe"
    $PayloadSource     = Join-Path $PayloadRoot "tools\nssm.exe"

    Ensure-Directory -Path $NssmStableDir

    if (Test-Path $NssmExe) {
        Write-Host "[OK] NSSM already installed: $NssmExe" -ForegroundColor Green
        return
    }

    if (Test-Path $ThirdPartySource) {
        Copy-Item $ThirdPartySource $NssmExe -Force
        Write-Host "[OK] NSSM copied from third_party folder" -ForegroundColor Green
        return
    }

    if (Test-Path $RepoSource) {
        Copy-Item $RepoSource $NssmExe -Force
        Write-Host "[OK] NSSM copied from Repo A tools folder" -ForegroundColor Green
        return
    }

    if (Test-Path $PayloadSource) {
        Copy-Item $PayloadSource $NssmExe -Force
        Write-Host "[OK] NSSM copied from payload tools folder" -ForegroundColor Green
        return
    }

    Write-Host "NSSM not found locally. Downloading..." -ForegroundColor Yellow

    $ZipUrl  = "https://nssm.cc/release/nssm-2.24.zip"
    $ZipFile = "$env:TEMP\nssm.zip"
    $TmpDir  = "$env:TEMP\nssm_extract"

    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile

    if (Test-Path $TmpDir) {
        Remove-Item $TmpDir -Recurse -Force
    }

    Expand-Archive $ZipFile -DestinationPath $TmpDir

    $DownloadedExe = Get-ChildItem $TmpDir -Recurse -Filter nssm.exe |
        Where-Object { $_.FullName -like "win64" } |
        Select-Object -First 1

    if (-not $DownloadedExe) {
        throw "Failed to locate win64\nssm.exe in downloaded archive"
    }

    Copy-Item $DownloadedExe.FullName $NssmExe -Force

    Write-Host "[OK] NSSM downloaded and installed to $NssmExe" -ForegroundColor Green
}

function Stop-And-Remove-ExistingServices {
    Write-Phase "Stopping and removing existing services"

    foreach ($svc in $Services) {
        $name = $svc.Name
        $existing = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($existing) {
            try {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }
            catch {
            }

            & sc.exe delete $name | Out-Null
            Start-Sleep -Seconds 2
            Write-Host "[OK] Removed existing service: $name" -ForegroundColor Green
        }
    }
}

function Reset-GreenSlot {
    Write-Phase "Resetting GREEN slot"

    if (Test-Path $GreenRoot) {
        Remove-Item -Recurse -Force $GreenRoot -ErrorAction SilentlyContinue
    }

    Ensure-Directory -Path $GreenRoot
    Write-Host "[OK] Prepared $GreenRoot" -ForegroundColor Green
}

function Stage-Payload {
    Write-Phase "Staging installer_payload to GREEN slot"

    if (-not (Test-Path $PayloadRoot)) {
        throw "installer_payload not found at $PayloadRoot"
    }

    Copy-Item -Path (Join-Path $PayloadRoot "*") -Destination $GreenRoot -Recurse -Force
    Write-Host "[OK] Payload staged to $GreenRoot" -ForegroundColor Green
}

function Ensure-Secrets {
    Write-Phase "Ensuring secrets"

    Ensure-Directory -Path $SecretRoot

    if (-not (Test-Path $SecretFile)) {
        throw "Required secret file missing: $SecretFile"
    }

    Write-Host "[OK] Found env.json at $SecretFile" -ForegroundColor Green
}

function Ensure-Venv-And-Dependencies {
    Write-Phase "Creating venv and installing requirements"

    $venvRoot = Join-Path $GreenRoot "venv"
    $venvPy   = Join-Path $venvRoot "Scripts\python.exe"

    if (-not (Test-Path $venvPy)) {
        & $Python314 -m venv $venvRoot
    }

    if (-not (Test-Path $venvPy)) {
        throw "venv python missing after creation: $venvPy"
    }

    & $venvPy -m pip install --upgrade pip setuptools wheel

    $requirementsCandidates = @(
        (Join-Path $GreenRoot "forensic_suite_v2\scripts\requirements.txt"),
        (Join-Path $GreenRoot "requirements.txt")
    )

    $requirementsFile = $requirementsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($requirementsFile) {
        Write-Host "Installing requirements from $requirementsFile" -ForegroundColor Yellow
        & $venvPy -m pip install -r $requirementsFile
    }
    else {
        Write-Host "[WARN] No requirements.txt found in staged payload" -ForegroundColor Yellow
    }

    $wheelDir = Join-Path $GreenRoot "wheel"
    $wheel = Get-ChildItem $wheelDir -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($wheel) {
        Write-Host "Installing wheel $($wheel.Name)" -ForegroundColor Yellow
        & $venvPy -m pip install --upgrade --force-reinstall $wheel.FullName
    }
    else {
        Write-Host "[WARN] No wheel found in $wheelDir" -ForegroundColor Yellow
    }

    Write-Host "[OK] venv prepared at $venvRoot" -ForegroundColor Green
}

function Switch-RuntimeSymlink {
    Write-Phase "Switching runtime symlink to GREEN"

    if (Test-Path $RuntimeLink) {
        Remove-Item $RuntimeLink -Force
    }

    New-Item -ItemType SymbolicLink -Path $RuntimeLink -Target $GreenRoot | Out-Null
    Write-Host "[OK] $RuntimeLink -> $GreenRoot" -ForegroundColor Green
}

function Install-ServicesWithNSSM {
    Write-Phase "Installing services with NSSM"

    Ensure-Directory -Path $LogsRoot

    $venvPy = Join-Path $RuntimeLink "venv\Scripts\python.exe"
    if (-not (Test-Path $venvPy)) {
        throw "Runtime venv python missing: $venvPy"
    }

    foreach ($svc in $Services) {
        $name       = $svc.Name
        $scriptPath = Join-Path $RuntimeLink $svc.Script

        if (-not (Test-Path $scriptPath)) {
            Write-Host "[SKIP] $name script not found: $scriptPath" -ForegroundColor Yellow
            continue
        }

        $existing = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $existing) {
            & $NssmExe install $name $venvPy | Out-Null
        }
        else {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        }

        if ($svc.Type -eq "powershell") {
            & $NssmExe set $name Application "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null
            & $NssmExe set $name AppParameters "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" | Out-Null
        }
        else {
            & $NssmExe set $name Application $venvPy | Out-Null
            & $NssmExe set $name AppParameters "`"$scriptPath`"" | Out-Null
        }

        & $NssmExe set $name AppDirectory $RuntimeLink | Out-Null
        & $NssmExe set $name AppEnvironmentExtra "PYTHONPATH=$RuntimeLink" "PYTHONUNBUFFERED=1" | Out-Null
        & $NssmExe set $name Start SERVICE_AUTO_START | Out-Null
        & $NssmExe set $name AppExit Default Restart | Out-Null

        $stdoutLog = Join-Path $LogsRoot "$name.out.log"
        $stderrLog = Join-Path $LogsRoot "$name.err.log"

        & $NssmExe set $name AppStdout $stdoutLog | Out-Null
        & $NssmExe set $name AppStderr $stderrLog | Out-Null

        Write-Host "[OK] Configured service: $name" -ForegroundColor Green
    }
}

function Start-And-Verify-Services {
    Write-Phase "Starting and verifying services"

    foreach ($svc in $Services) {
        $name = $svc.Name
        try {
            Start-Service -Name $name -ErrorAction Stop
            Write-Host "[OK] Started $name" -ForegroundColor Green
        }
        catch {
            Write-Host "[FAIL] Could not start $name : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Service state summary:" -ForegroundColor Cyan

    foreach ($svc in $Services) {
        $name = $svc.Name
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host ("  {0} => {1}" -f $name, $service.Status)
            & sc.exe queryex $name | Select-String -Pattern "STATE|WIN32_EXIT_CODE|SERVICE_EXIT_CODE|PID" | ForEach-Object { "    $($_.Line.Trim())" }
        }
        else {
            Write-Host ("  {0} => NOT FOUND" -f $name) -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Recent Service Control Manager events:" -ForegroundColor Cyan
    Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Service Control Manager" } -MaxEvents 20 |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Format-Table -AutoSize
}

# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------
Assert-Admin
Ensure-ServicesPipeTimeout
Ensure-Python314
Ensure-NSSM
Stop-And-Remove-ExistingServices
Reset-GreenSlot
Stage-Payload
Ensure-Secrets
Ensure-Venv-And-Dependencies
Switch-RuntimeSymlink
Install-ServicesWithNSSM
Start-And-Verify-Services

Write-Host ""
Write-Host "=== TEST INSTALL COMPLETE ===" -ForegroundColor Cyan
