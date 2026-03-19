# =====================================================================
# FORENSIC SUITE V2 - MASTER DEVELOPMENT PROFILE (V9.0 - STABLE)
# =====================================================================

# --- GLOBAL CONSTANTS ------------------------------------------------
$Global:PrimaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$Global:ClusterIPs = @("192.168.0.199", "192.168.0.28", "192.168.0.146", "192.168.0.165")
$Global:SSHKey = "$env:USERPROFILE\.ssh\id_ed25519"
$Global:HostList = "F:\tools\forensic_hosts.txt"
$Global:Creds = @{
    "192.168.0.146" = Get-Credential "SELVON\forensicuser"
    "192.168.0.199" = Get-Credential "WIN-1V7900SUQ9A\forensicuser"
    "192.168.0.165" = Get-Credential "WIN-8ENVN7I0JFE\forensicuser"
    "192.168.0.28"  = Get-Credential "Louis-HP\forensicuser"
}

# =====================================================================
# 1. DEVELOPMENT & SYNC
# =====================================================================

function Sync-Dev {
    param([switch]$Apply)
    $MappingCsv = "F:\tools\repo_mapping_suite.csv"

    Write-Host "`n>>> Regenerating Repo Mapping..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\scripts\forensic_suite_repo_mapping.ps1" -OutCsv $MappingCsv

    if ($Apply) {
        & "$Global:PrimaryRoot\scripts\Sync-DevTrees.Apply.ps1" -MappingCsv $MappingCsv
    } else {
        & "$Global:PrimaryRoot\scripts\Sync-DevTrees.DryRun.ps1" -MappingCsv $MappingCsv
        Write-Host "[INFO] Run Sync-Dev -Apply to commit changes to Repo B." -ForegroundColor Yellow
    }

    Write-Host "`n>>> Refreshing Local Python Environment..." -ForegroundColor Cyan
    Push-Location $Global:PrimaryRoot
    python -m pip install -e .
    Pop-Location
}

function Sync-Validate {
    Write-Host "`n>>> Verifying Mirror Integrity (Strict Scope)..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\scripts\Sync-DevTrees.Validate.ps1"
}

# =====================================================================
# 2. INSTALLATION & BUILD
# =====================================================================
function Test-Install {
    Write-Host "`n>>> Executing Local Clean-Slate Installation Test..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\test_install.ps1"
}

function Build-Suite {

    $ErrorActionPreference = "Stop"

    # ----------------------------------------------------------------------
    # LOGGING SETUP
    # ----------------------------------------------------------------------
    $LogRoot = Join-Path $Global:PrimaryRoot "logs"
    if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot | Out-Null }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogRoot "BuildSuite_$Timestamp.log"

    function Log {
        param([string]$msg)
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
        Add-Content -Path $LogFile -Value $line
        Write-Host $msg
    }

    Log "=== Build-Suite START ==="
    Log "PrimaryRoot = $Global:PrimaryRoot"
    Log "LogFile     = $LogFile"

    # Track total runtime
    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {

        # ==================================================================
        # 1. BUILD WHEEL + PYINSTALLER BUNDLE
        # ==================================================================
        Log "[1/4] Building wheel + PyInstaller bundle..."
        $t = [System.Diagnostics.Stopwatch]::StartNew()

        & "$Global:PrimaryRoot\build_final.ps1" -BuildOnly
        if ($LASTEXITCODE -ne 0) {
            Log "[ERROR] Step 1 failed with exit code $LASTEXITCODE"
            return 101
        }

        $t.Stop()
        Log "[1/4] Completed in $($t.Elapsed.ToString())"


        # ==================================================================
        # 2. REFRESH INSTALLER PAYLOAD
        # ==================================================================
        Log "[2/4] Refreshing installer_payload from Repo A..."
        $t = [System.Diagnostics.Stopwatch]::StartNew()

        & "$Global:PrimaryRoot\refresh_installer_payload.ps1"
        if ($LASTEXITCODE -ne 0) {
            Log "[ERROR] Step 2 failed with exit code $LASTEXITCODE"
            return 102
        }

        $t.Stop()
        Log "[2/4] Completed in $($t.Elapsed.ToString())"


        # ==================================================================
        # 3. BUILD INSTALLER EXE
        # ==================================================================
        Log "[3/4] Building installer EXE..."
        $t = [System.Diagnostics.Stopwatch]::StartNew()

        & "$Global:PrimaryRoot\build_and_deploy.ps1" -BuildOnly
        if ($LASTEXITCODE -ne 0) {
            Log "[ERROR] Step 3 failed with exit code $LASTEXITCODE"
            return 103
        }

        $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
        if (-not (Test-Path $InstallerExe)) {
            Log "[ERROR] Installer EXE missing after build."
            return 104
        }

        $t.Stop()
        Log "[3/4] Completed in $($t.Elapsed.ToString())"
        Log "Installer EXE: $InstallerExe"


        # ==================================================================
        # 4. POST-INSTALL VALIDATION
        # ==================================================================
        Log "[4/4] Running post-install validation..."
        $t = [System.Diagnostics.Stopwatch]::StartNew()

        & "$Global:PrimaryRoot\post_install_validation.ps1" -InstallerExe $InstallerExe
        if ($LASTEXITCODE -ne 0) {
            Log "[ERROR] Step 4 failed with exit code $LASTEXITCODE"
            return 105
        }

        $t.Stop()
        Log "[4/4] Completed in $($t.Elapsed.ToString())"


        # ==================================================================
        # SUCCESS SUMMARY
        # ==================================================================
        $TotalTimer.Stop()
        Log "=== Build-Suite COMPLETED SUCCESSFULLY ==="
        Log "Total Runtime: $($TotalTimer.Elapsed.ToString())"
        Log "Installer payload refreshed and validated."
        Log "Installer EXE: $InstallerExe"

        return 0
    } catch {
        $TotalTimer.Stop()
        Log "[FATAL] Unhandled exception: $_"
        Log "Total Runtime before failure: $($TotalTimer.Elapsed.ToString())"
        return 199
    }
}

# =====================================================================
# 3. DEPLOYMENT & SECRETS
# =====================================================================
function Deploy-Host {
    param([Parameter(Mandatory = $true)][string]$IP, [switch]$BlueGreen)
    $Installer = "$Global:PrimaryRoot\Output\ForensicSuiteV2-Setup.exe"
    & "$Global:PrimaryRoot\deploy_suite.ps1" -TargetHost $IP -InstallerPath $Installer -BlueGreen:$BlueGreen
}
function Deploy-Host-Hardened {
    param(
        [Parameter(Mandatory = $true)][string]$IP,
        [switch]$BlueGreen
    )

    $ErrorActionPreference = "Stop"

    # ----------------------------------------------------------------------
    # LOGGING SETUP
    # ----------------------------------------------------------------------
    $LogRoot = Join-Path $Global:PrimaryRoot "logs"
    if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot | Out-Null }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogRoot "DeployHost_${IP}_$Timestamp.log"

    function Log {
        param([string]$msg)
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
        Add-Content -Path $LogFile -Value $line
        Write-Host $msg
    }

    Log "=== Deploy-Host-Hardened START ==="
    Log "TargetHost = $IP"
    Log "BlueGreen  = $BlueGreen"
    Log "LogFile    = $LogFile"

    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # ==================================================================
        # 1. BUILD SUITE (HARDENED)
        # ==================================================================
        Log "[1/3] Invoking Build-Suite (hardened)..."
        $buildCode = Build-Suite
        if ($buildCode -ne 0) {
            Log "[ERROR] Build-Suite failed with code $buildCode. Aborting deploy."
            $TotalTimer.Stop()
            return 301
        }

        $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
        if (-not (Test-Path $InstallerExe)) {
            Log "[ERROR] Installer EXE missing after Build-Suite: $InstallerExe"
            $TotalTimer.Stop()
            return 302
        }

        Log "[1/3] Build-Suite completed successfully. Installer: $InstallerExe"


        # ==================================================================
        # 2. DEPLOY TO TARGET HOST
        # ==================================================================
        Log "[2/3] Deploying to $IP..."
        $deployTimer = [System.Diagnostics.Stopwatch]::StartNew()

        & "$Global:PrimaryRoot\deploy_suite.ps1" `
            -TargetHost $IP `
            -InstallerPath $InstallerExe `
            -BlueGreen:$BlueGreen

        $deployCode = $LASTEXITCODE
        $deployTimer.Stop()

        if ($deployCode -ne 0) {
            Log "[ERROR] Deploy to $IP failed with code $deployCode after $($deployTimer.Elapsed.ToString())."
            $TotalTimer.Stop()
            return 303
        }

        Log "[2/3] Deploy to $IP completed successfully in $($deployTimer.Elapsed.ToString())."


        # ==================================================================
        # 3. POST-DEPLOY VALIDATION (REMOTE)
        # ==================================================================
        Log "[3/3] Validating remote installation on $IP..."

        $validationTimer = [System.Diagnostics.Stopwatch]::StartNew()

        $remoteCheck = ssh -i $Global:SSHKey "forensicuser@$IP" `
            'powershell -Command "if (Test-Path C:\forensic_suite_v2) { Write-Host OK } else { Write-Host MISSING }"'

        $validationTimer.Stop()

        if ($remoteCheck -notmatch "OK") {
            Log "[ERROR] Remote validation failed on $IP after $($validationTimer.Elapsed.ToString())."
            $TotalTimer.Stop()
            return 304
        }

        Log "[3/3] Remote validation succeeded on $IP in $($validationTimer.Elapsed.ToString())."


        # ==================================================================
        # SUCCESS SUMMARY
        # ==================================================================
        $TotalTimer.Stop()
        Log "=== Deploy-Host-Hardened COMPLETED SUCCESSFULLY ==="
        Log "Total Runtime: $($TotalTimer.Elapsed.ToString())"
        Log "Installer EXE: $InstallerExe"

        return 0
    } catch {
        $TotalTimer.Stop()
        Log "[FATAL] Unhandled exception during Deploy-Host-Hardened: $_"
        Log "Total runtime before failure: $($TotalTimer.Elapsed.ToString())"
        return 399
    }
}
function Deploy-Cluster {
    param([switch]$BlueGreen)
    Write-Host "`n>>> Deploying Installer to Cluster via SSH..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\build_and_deploy.ps1" -Deploy -BlueGreen:$BlueGreen
}
function Deploy-Cluster-Hardened {
    param(
        [switch]$BlueGreen
    )

    $ErrorActionPreference = "Stop"

    # ----------------------------------------------------------------------
    # LOGGING SETUP
    # ----------------------------------------------------------------------
    $LogRoot = Join-Path $Global:PrimaryRoot "logs"
    if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot | Out-Null }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogRoot "DeployCluster_$Timestamp.log"

    function Log {
        param([string]$msg)
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
        Add-Content -Path $LogFile -Value $line
        Write-Host $msg
    }

    Log "=== Deploy-Cluster-Hardened START ==="
    Log "PrimaryRoot = $Global:PrimaryRoot"
    Log "LogFile     = $LogFile"
    Log "BlueGreen   = $BlueGreen"

    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    $Hosts = $Global:ClusterIPs

    # Per-host results
    $Results = @()

    try {
        # ==================================================================
        # 1. BUILD + VALIDATE SUITE (PRECONDITION)
        # ==================================================================
        Log "[1/3] Invoking Build-Suite (hardened)..."
        $buildCode = Build-Suite
        if ($buildCode -ne 0) {
            Log "[ERROR] Build-Suite failed with code $buildCode. Aborting deploy."
            $TotalTimer.Stop()
            return 201
        }

        if (-not (Test-Path $InstallerExe)) {
            Log "[ERROR] Installer EXE missing after Build-Suite: $InstallerExe"
            $TotalTimer.Stop()
            return 202
        }

        Log "[1/3] Build-Suite completed successfully. Installer: $InstallerExe"


        # ==================================================================
        # 2. DEPLOY TO EACH HOST (BLUE/GREEN AWARE)
        # ==================================================================
        Log "[2/3] Deploying to cluster nodes..."
        foreach ($ip in $Hosts) {
            $hostTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $hostLog = Join-Path $LogRoot "DeployHost_${ip}_$Timestamp.log"

            function HostLog {
                param([string]$msg)
                $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
                Add-Content -Path $hostLog -Value $line
                Write-Host $msg
            }

            HostLog "=== Deploying to $ip ==="
            HostLog "Installer: $InstallerExe"

            $hostStatus = "Unknown"
            $hostCode = 0

            try {
                $deployTimer = [System.Diagnostics.Stopwatch]::StartNew()

                & "$Global:PrimaryRoot\deploy_suite.ps1" `
                    -TargetHost $ip `
                    -InstallerPath $InstallerExe `
                    -BlueGreen:$BlueGreen

                $hostCode = $LASTEXITCODE

                $deployTimer.Stop()

                if ($hostCode -eq 0) {
                    $hostStatus = "Success"
                    HostLog "[OK] Deploy to $ip completed in $($deployTimer.Elapsed.ToString())."
                } else {
                    $hostStatus = "Failed"
                    HostLog "[ERROR] Deploy to $ip failed with code $hostCode after $($deployTimer.Elapsed.ToString())."
                }
            } catch {
                $hostStatus = "Exception"
                $hostCode = 299
                HostLog "[FATAL] Exception during deploy to ${ip}: $_"
            }

            $hostTimer.Stop()
            HostLog "=== Deploy to $ip finished. Status: $hostStatus. Total: $($hostTimer.Elapsed.ToString()) ==="

            $Results += [PSCustomObject]@{
                Host   = $ip
                Status = $hostStatus
                Code   = $hostCode
                Log    = $hostLog
            }
        }


        # ==================================================================
        # 3. CLUSTER SUMMARY + ERROR CODE
        # ==================================================================
        Log "[3/3] Cluster deployment summary:"
        foreach ($r in $Results) {
            Log ("  {0} : {1} (Code {2}) Log={3}" -f $r.Host, $r.Status, $r.Code, $r.Log)
        }

        $TotalTimer.Stop()
        Log "Total Deploy-Cluster-Hardened runtime: $($TotalTimer.Elapsed.ToString())"

        $failed = $Results | Where-Object { $_.Status -ne "Success" }

        if ($failed.Count -gt 0) {
            Log "[WARNING] One or more hosts failed deployment."
            return 210
        }

        Log "=== Deploy-Cluster-Hardened COMPLETED SUCCESSFULLY ==="
        return 0
    } catch {
        $TotalTimer.Stop()
        Log "[FATAL] Unhandled exception in Deploy-Cluster-Hardened: $_"
        Log "Total runtime before failure: $($TotalTimer.Elapsed.ToString())"
        return 299
    }
}

function Sync-Secrets {
    Write-Host "`n>>> Provisioning REAL Secrets (env.json) to Cluster..." -ForegroundColor Magenta

    $LocalSecret = Join-Path $Global:PrimaryRoot "env.json"
    if (!(Test-Path $LocalSecret)) {
        Write-Error "CRITICAL: Local env.json missing! Populate it before syncing."
        return
    }

    foreach ($ip in $Global:ClusterIPs) {
        Write-Host ">>> Patching Node: $ip" -ForegroundColor Cyan
        scp -i $Global:SSHKey "$LocalSecret" "forensicuser@${ip}:F:\forensic_secrets\env.json"
        ssh -i $Global:SSHKey "forensicuser@$ip" "icacls F:\forensic_secrets\env.json /grant SYSTEM:(R)"
    }

    Write-Host "[SUCCESS] All nodes provisioned with production credentials." -ForegroundColor Green
}

# =====================================================================
# 4. HEALTH & MONITORING
# =====================================================================

function Status-Report {
    Write-Host "`n=== FORENSIC SUITE STATUS REPORT (V8.2) ===" -ForegroundColor Cyan

    foreach ($ip in $Global:ClusterIPs) {
        $ping = if (Test-Connection -ComputerName $ip -Count 1 -Quiet) { "UP" } else { "DOWN" }
        $svcStatus = "UNKNOWN"

        if ($ping -eq "UP") {
            $svcStatus = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "if(Get-Service tron_indexer -ErrorAction SilentlyContinue){Get-Service tron_indexer | Select-Object -ExpandProperty Status}else{Write-Host MISSING}"'
        }

        $color = if ($svcStatus -eq "Running") { "Green" } elseif ($ping -eq "UP") { "Yellow" } else { "Red" }
        Write-Host "  $ip : PING($ping) | SERVICE($svcStatus)" -ForegroundColor $color
    }
}

# =====================================================================
# 5. UNINSTALL ORCHESTRATION
# =====================================================================
function Invoke-ForensicUninstall {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Minimal", "Full")][string]$Mode,
        [string]$TargetHost
    )
    $Hosts = if ($TargetHost) { @($TargetHost) } else { $Global:ClusterIPs }
    foreach ($ip in $Hosts) {
        Write-Host "`n>>> Wiping Node $ip..." -ForegroundColor Cyan
        # Explicit PowerShell syntax to avoid CMD /q parameter errors
        $cleanCmd = "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue; " +
        "Remove-Item C:\forensic_suite_v2, C:\forensic_suite_v2_blue, C:\forensic_suite_v2_green -Recurse -Force -ErrorAction SilentlyContinue; " +
        "Remove-Item C:\forensic_suite_v2_installer.exe -Force -ErrorAction SilentlyContinue"
        ssh -i $Global:SSHKey "forensicuser@$ip" "powershell -Command `"$cleanCmd`""
        Write-Host "[OK] Clean slate achieved for $ip." -ForegroundColor Green
    }
}

# =====================================================================
# 6. DASHBOARD SHORTCUT
# =====================================================================

function dashboard {
    & "F:\tools\ForensicSuiteV2-Operations.ps1" -Dashboard -Verbose -HostList $Global:HostList
}

# =====================================================================
# 7. RE-INSTALL TO ALL HOSTS
# =====================================================================
function fs-reinstall {
    param(
        [string]$TargetHost,
        [string]$HostList = "F:\tools\forensic_hosts.txt",
        [ValidateSet("Minimal", "Full")]
        [string]$Mode = "Full"
    )

    $script = "F:\tools\ForensicSuiteV2-Reinstall.ps1"

    if ($TargetHost) {
        & $script -Host $TargetHost -Mode $Mode
    } else {
        & $script -HostList $HostList -Mode $Mode
    }
}


# =====================================================================
# 8. HELP
# =====================================================================
function fs-help {
    Write-Host "`n=== FORENSIC SUITE V2 – COMMAND REFERENCE ===" -ForegroundColor Cyan

    Write-Host "`n[ Development ]" -ForegroundColor Yellow
    Write-Host "  Sync-Dev            – Refresh editable Python install"
    Write-Host "  Sync-Validate       – Validate the refresh from Sync-Dev -Applyl"
    Write-Host "  Test-Install        – Run local clean-slate install test"
    Write-Host "  Build-Suite         – Build wheel + hardened EXE"

    Write-Host "`n[ Deployment ]" -ForegroundColor Yellow
    Write-Host "  Deploy-Host         – Deploy installer to a single host"
    Write-Host "  Deploy-Host-Hardened         – Deploy installer to a single host"

    Write-Host "  Deploy-Cluster      – Build + deploy to all cluster nodes"
    Write-Host "  Deploy-Cluster-Hardened – Build + deploy hardened installer to all cluster nodes"


    Write-Host "`n[ Secrets & Config ]" -ForegroundColor Yellow
    Write-Host "  Sync-Secrets        – Push env.json to all nodes"

    Write-Host "`n[ Monitoring ]" -ForegroundColor Yellow
    Write-Host "  Status-Report       – Ping + service health across cluster"
    Write-Host "  dashboard           – Launch dashboard status view"

    Write-Host "`n[ Uninstall / Recovery ]" -ForegroundColor Yellow
    Write-Host "  Invoke-ForensicUninstall – Minimal/Full/Rollback/Cluster/Diff"
    Write-Host "  fs-reinstall        – Full clean reinstall on host(s)"

    Write-Host "`n[ Misc ]" -ForegroundColor Yellow
    Write-Host "  fs-help             – Show this command reference"

    Write-Host "`nWorkspace ready." -ForegroundColor Green
}


# =====================================================================
# 9. PROMPT CUSTOMIZATION
# =====================================================================

function prompt { "Forensic-Dev [$(Split-Path -Leaf $pwd)]> " }

Write-Host "`nForensic Suite Workspace V9.0 Loaded." -ForegroundColor Gray
Write-Host "Commands: Sync-Dev, Sync-Validate, Test-Install, Build-Suite, Deploy-Host, Deploy-Host-Hardened, Deploy-Cluster, Deploy-Cluster-Hardened, Sync-Secrets, Status-Report, Invoke-ForensicUninstall, fs-reinstall, fs-help, dashboard" -ForegroundColor Gray
