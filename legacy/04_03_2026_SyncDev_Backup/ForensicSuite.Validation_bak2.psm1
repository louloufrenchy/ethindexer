# =====================================================================
# ForensicSuite.Validation.psm1 (V9.4)
# Unified Validation + Sync-Dev + Cleanup Module
# =====================================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- 1. CORE UTILITIES -----------------------------------------------

function Clean-All {
    Write-Host "`n>>> Cleaning Repo A + Repo B..." -ForegroundColor Cyan
    & "$ScriptRoot\forensic_suite_RepoB_cleanup.ps1"
}

function Validate-All {
    Write-Host "`n>>> Running Combined Validation..." -ForegroundColor Cyan
    & "$ScriptRoot\forensic_suite_Combined_validator.ps1"
}

function Repair-Workspace {
    Write-Host "`n>>> Repairing Workspace (Clean + Sync-Dev)..." -ForegroundColor Cyan
    Clean-All
    Sync-Dev -Apply
}

# --- 2. DEVELOPMENT & SYNC -------------------------------------------

function Sync-Dev {
    param([switch]$Apply)

    $FullSuite = Join-Path $Global:PrimaryRoot "scripts\Sync-DevTrees.FullSuite.ps1"

    if (!(Test-Path $FullSuite)) {
        Write-Host "[ERROR] Sync-DevTrees.FullSuite.ps1 not found at $FullSuite" -ForegroundColor Red
        return
    }

    if ($Apply) {
        Write-Host ">>> Running Sync-Dev FULL APPLY (V9.4)..." -ForegroundColor Cyan
        & $FullSuite -ForceApply
    } else {
        Write-Host ">>> Running Sync-Dev DRY RUN (V9.4)..." -ForegroundColor Cyan
        & $FullSuite
    }
}

function Sync-Validate {
    Write-Host "`n>>> Verifying Mirror Integrity..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\scripts\Sync-DevTrees.Validate.ps1"
}

# --- 3. BUILD PIPELINE -----------------------------------------------

function Invoke-Preflight {
    Write-Host "`n>>> Running Preflight (Repo A + Repo B)..." -ForegroundColor Cyan
    Validate-All
    return $LASTEXITCODE
}

function Build-Suite {
    param([switch]$Force)
    $ErrorActionPreference = "Stop"

    $pre = Invoke-Preflight
    if ($pre -ne 0) { Write-Host "[ABORT] Build blocked by preflight." -ForegroundColor Red; return $pre }

    # Change this:
	# $RepoRoot = Split-Path $Global:PrimaryRoot -Parent

	# To this (explicitly use the PrimaryRoot for script lookups):
	$RepoRoot = $Global:PrimaryRoot
    Write-Host "`n>>> Starting Deterministic Build Pipeline..." -ForegroundColor Cyan

    try {
        # 1. Wheel + PyInstaller
        & (Join-Path $RepoRoot "build_final.ps1") -BuildOnly
        
        # 2. Refresh Payload
        & (Join-Path $RepoRoot "refresh_installer_payload.ps1")
        
        # 3. Build Installer EXE
        & (Join-Path $RepoRoot "build_and_deploy.ps1") -BuildOnly
        
        # 4. Final Integrity Check
        & (Join-Path $Global:PrimaryRoot "scripts\validate_installer_payload.ps1")
        
        Write-Host "[SUCCESS] Build-Suite Completed." -ForegroundColor Green
        return 0
    } catch {
        Write-Host "[FATAL] Build failed: $_" -ForegroundColor Red
        return 199
    }
	Get-Command -Module ForensicSuite.Validation
}

function Safe-BuildSuite {
    Clean-All
    Build-Suite
}

# --- 4. DEPLOYMENT ---------------------------------------------------

function Invoke-DeployPreflight {
    Write-Host "`n>>> Running Deployment Preflight..." -ForegroundColor Cyan
    $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    if (!(Test-Path $InstallerExe)) { Write-Host "[FAIL] Installer EXE missing." -ForegroundColor Red; return 203 }
    Write-Host "[OK] Preflight Passed." -ForegroundColor Green
    return 0
}

function Deploy-Host {
    param([Parameter(Mandatory=$true)][string]$IP, [switch]$BlueGreen)
    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return }
    & "$Global:PrimaryRoot\deploy_suite.ps1" -TargetHost $IP -BlueGreen:$BlueGreen
	Get-Command -Module ForensicSuite.Validation
}

function Deploy-Cluster {
    param([switch]$BlueGreen)
    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return }
    & "$Global:PrimaryRoot\build_and_deploy.ps1" -Deploy -BlueGreen:$BlueGreen
	Get-Command -Module ForensicSuite.Validation
}

function Sync-Secrets {
    Write-Host "`n>>> Syncing Secrets to Cluster..." -ForegroundColor Magenta
    $LocalSecret = Join-Path $Global:PrimaryRoot "env.json"
    foreach ($ip in $Global:ClusterIPs) {
        scp -i $Global:SSHKey "$LocalSecret" "forensicuser@${ip}:F:\forensic_secrets\env.json"
        ssh -i $Global:SSHKey "forensicuser@$ip" "icacls F:\forensic_secrets\env.json /grant SYSTEM:(R)"
    }
	Get-Command -Module ForensicSuite.Validation
}

# --- 5. OPERATIONS & MONITORING --------------------------------------

function Status-Report {
    Write-Host "`n=== FORENSIC SUITE CLUSTER STATUS (V9.4) ===" -ForegroundColor Cyan
    foreach ($ip in $Global:ClusterIPs) {
        $ping = if (Test-Connection -ComputerName $ip -Count 1 -Quiet) { "UP" } else { "DOWN" }
        if ($ping -eq "UP") {
            # Standardizing output to avoid Parser Error
            $svcStatus = ssh -i $Global:SSHKey "forensicuser@${ip}" 'powershell -Command "Get-Service tron_indexer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status"'
            $color = if ($svcStatus -eq "Running") { "Green" } else { "Yellow" }
            
            Write-Host ("  {0}" -f $ip) -ForegroundColor $color
            Write-Host "     PING:    $ping"
            Write-Host "     SERVICE: $svcStatus"
        } else {
            Write-Host "  $ip : DOWN" -ForegroundColor Red
        }
    }
	Get-Command -Module ForensicSuite.Validation
}

# --- 6. PROMPT & EXPORTS ---------------------------------------------

function prompt { "Forensic-Dev [$(Split-Path -Leaf $pwd)]> " }

Export-ModuleMember -Function Clean-All, Validate-All, Sync-Dev, Sync-Validate, Safe-BuildSuite, Build-Suite, Deploy-Host, Deploy-Cluster, Status-Report, Sync-Secrets, Repair-Workspace

Write-Host "`nForensic Suite Validation Module V9.4 Loaded." -ForegroundColor Gray
Get-Command -Module ForensicSuite.Validation
Write-Host "Modules Imported: Clean-All, Validate-All, Sync-Dev, Sync-Validate, Safe-BuildSuite, Build-Suite, Deploy-Host, Deploy-Cluster, Status-Report, Sync-Secrets, Repair-Workspace"
Write-Host "Type: Get-Command -Module ForensicSuite.Validation to see all modules available." -ForegroundColor Gray
