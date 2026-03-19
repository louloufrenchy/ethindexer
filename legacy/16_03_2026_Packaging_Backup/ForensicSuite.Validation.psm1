# =====================================================================
# ForensicSuite.Validation.psm1 (V9.3.2)
# Unified Validation + Update-ForensicSuiteDev + Cleanup + Deploy + Status Module
# =====================================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# =====================================================================
# 1. CLEANUP & VALIDATION
# =====================================================================

function Clear-ForensicSuiteAll {
    & "$ScriptRoot\forensic_suite_RepoB_cleanup.ps1"
}

function Test-ForensicSuiteAll {
    & "$ScriptRoot\forensic_suite_Combined_validator.ps1"
}

function Repair-Workspace {
    Write-Host "`n>>> Repairing workspace (Clear-ForensicSuiteAll + Update-ForensicSuiteDev -Apply)..." -ForegroundColor Cyan
    $clean = Clear-ForensicSuiteAll
    if ($clean -ne 0) {
        Write-Host "[ABORT] Repair blocked." -ForegroundColor Red
        return $clean
    }
    Update-ForensicSuiteDev -Apply
}

# =====================================================================
# 2. PRE-FLIGHT WRAPPER
# =====================================================================

function Invoke-Preflight {
    Write-Host "`n>>> Running Preflight (Repo A + Repo B validators)..." -ForegroundColor Cyan

    Test-ForensicSuiteAll
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Host "[BLOCKED] Preflight failed with code $code." -ForegroundColor Red
    } else {
        Write-Host "[OK] Preflight passed." -ForegroundColor Green
    }

    return $code
}

# =====================================================================
# 3. DEVELOPMENT & SYNC (V9.3 ATOMIC SYNC-DEV)
# =====================================================================

function Update-ForensicSuiteDev {
    param(
        [switch]$Apply
    )

    $FullSuite = Join-Path $Global:PrimaryRoot "scripts\Sync-DevTrees.FullSuite.ps1"

    if (!(Test-Path $FullSuite)) {
        Write-Host "[ERROR] FullSuite script not found at $FullSuite" -ForegroundColor Red
        return
    }

    if ($Apply) {
        Write-Host ">>> Running Sync‑Dev FULL APPLY (V9.3)..." -ForegroundColor Cyan
        & $FullSuite -ForceApply
    } else {
        Write-Host ">>> Running Sync‑Dev DRY RUN (V9.3)..." -ForegroundColor Cyan
        & $FullSuite
    }
}

Set-Alias syncdev Update-ForensicSuiteDev

function Update-ForensicSuiteValidation {
    Write-Host "`n>>> Verifying Mirror Integrity..." -ForegroundColor Cyan
    & (Join-Path $Global:PrimaryRoot "scripts\Sync-DevTrees.Validate.ps1")
}

# =====================================================================
# 4. INSTALLATION & BUILD
# =====================================================================

function Invoke-BuildSuiteSafe {
    Write-Host "`n>>> Running Clear-ForensicSuiteAll before Invoke-BuildSuite..." -ForegroundColor Cyan
    $clean = Clear-ForensicSuiteAll
    if ($clean -ne 0) {
        Write-Host "[ABORT] Invoke-BuildSuite blocked by Clear-ForensicSuiteAll." -ForegroundColor Red
        return $clean
    }
    Invoke-BuildSuite
}

function Invoke-BuildSuite {
    param(
        [switch]$Force
    )

    $ErrorActionPreference = "Stop"

    # ------------------------------------------------------------
    # Preflight
    # ------------------------------------------------------------
    $pre = Invoke-Preflight
    if ($pre -ne 0) {
        Write-Host "[ABORT] Invoke-BuildSuite blocked." -ForegroundColor Red
        return $pre
    }

    # ------------------------------------------------------------
    # Path anchors
    # ------------------------------------------------------------
    # PrimaryRoot = repo root
    # SuiteRoot   = forensic_suite_v2
    $RepoRoot  = $Global:PrimaryRoot
    $SuiteRoot = Join-Path $RepoRoot "forensic_suite_v2"

    # ------------------------------------------------------------
    # Logging
    # ------------------------------------------------------------
    $LogRoot = Join-Path $SuiteRoot "logs"
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile   = Join-Path $LogRoot "BuildSuite_$Timestamp.log"

    function Log {
        param([string]$msg)
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
        Add-Content -Path $LogFile -Value $line
        Write-Host $msg
    }

    Log "=== Invoke-BuildSuite START ==="
    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # --------------------------------------------------------
        # 1. Build wheel + PyInstaller bundle
        # --------------------------------------------------------
        Log "[1/5] Building wheel + PyInstaller bundle..."
        & (Join-Path $RepoRoot "build_final.ps1") -BuildOnly
        if ($LASTEXITCODE -ne 0) { return 101 }

        # --------------------------------------------------------
        # 2. Refresh installer payload
        # --------------------------------------------------------
        Log "[2/5] Refreshing installer_payload..."
        & (Join-Path $RepoRoot "refresh_installer_payload.ps1")
        if ($LASTEXITCODE -ne 0) { return 102 }

        # --------------------------------------------------------
        # 3. Build installer EXE
        # --------------------------------------------------------
        Log "[3/5] Building installer EXE..."
        & (Join-Path $RepoRoot "build_and_deploy.ps1") -BuildOnly
        if ($LASTEXITCODE -ne 0) { return 103 }

        $InstallerExe = Join-Path $RepoRoot "Output\ForensicSuiteV2-Setup.exe"
        if (-not (Test-Path $InstallerExe)) { return 104 }

        # --------------------------------------------------------
        # 4. Post-install validation
        # --------------------------------------------------------
        Log "[4/5] Running post-install validation..."
        & (Join-Path $RepoRoot "post_install_validation.ps1") -InstallerExe $InstallerExe
        if ($LASTEXITCODE -ne 0) { return 105 }

        # --------------------------------------------------------
        # 5. Installer payload integrity validation
        # --------------------------------------------------------
        Log "[5/5] Verifying installer payload integrity..."
        & (Join-Path $RepoRoot "scripts\validate_installer_payload.ps1")
        if ($LASTEXITCODE -ne 0) {
            Log "[FAIL] Installer payload validation failed with code $LASTEXITCODE"
            return 106
        }
        Log "[OK] Installer payload validated successfully."

        # --------------------------------------------------------
        # Success
        # --------------------------------------------------------
        $TotalTimer.Stop()
        Log "=== Invoke-BuildSuite COMPLETED SUCCESSFULLY ==="
        Log "Total Runtime: $($TotalTimer.Elapsed.ToString())"
        return 0
    }
    catch {
        $TotalTimer.Stop()
        Log "[FATAL] Unhandled exception: $_"
        return 199
    }
}

# =====================================================================
# 5. DEPLOYMENT & SECRETS
# =====================================================================

function Invoke-DeployPreflight {
    $ErrorActionPreference = "Stop"

    Write-Host "`n>>> Running Deploy-Suite Preflight..." -ForegroundColor Cyan

    # 1. Validate installer payload integrity
    $payloadValidator = Join-Path $Global:PrimaryRoot "scripts\validate_installer_payload.ps1"
    if (-not (Test-Path $payloadValidator)) {
        Write-Host "[BLOCKED] Missing validate_installer_payload.ps1" -ForegroundColor Red
        return 201
    }

    & $payloadValidator
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[BLOCKED] Installer payload integrity check failed." -ForegroundColor Red
        return 202
    }
    Write-Host "[OK] Installer payload integrity validated." -ForegroundColor Green

    # 2. Validate installer EXE exists
    $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    if (-not (Test-Path $InstallerExe)) {
        Write-Host "[BLOCKED] Installer EXE missing: $InstallerExe" -ForegroundColor Red
        return 203
    }
    Write-Host "[OK] Installer EXE found." -ForegroundColor Green

    # 3. Validate deployment scripts exist
    $deployScript = Join-Path $Global:PrimaryRoot "deploy_suite.ps1"
    if (-not (Test-Path $deployScript)) {
        Write-Host "[BLOCKED] Missing deploy_suite.ps1" -ForegroundColor Red
        return 204
    }

    $buildDeploy = Join-Path $Global:PrimaryRoot "build_and_deploy.ps1"
    if (-not (Test-Path $buildDeploy)) {
        Write-Host "[BLOCKED] Missing build_and_deploy.ps1" -ForegroundColor Red
        return 205
    }

    Write-Host "[OK] Deployment scripts validated." -ForegroundColor Green
    Write-Host "[OK] Deploy-Suite Preflight passed." -ForegroundColor Green
    return 0
}

function Get-DeploySuiteSummary {
    $ErrorActionPreference = "Stop"

    Write-Host "`n=== Deploy-Suite Summary Report (V9.3) ===" -ForegroundColor Cyan

    # Path anchors
    $root            = $Global:PrimaryRoot
    $dist            = Join-Path $root "dist"
    $payloadRoot     = Join-Path $root "installer_payload"
    $payloadWheelDir = Join-Path $payloadRoot "wheel"
    $payloadScripts  = Join-Path $payloadRoot "scripts"
    $srcScripts      = Join-Path $root "scripts"
    $installerExe    = Join-Path $root "Output\ForensicSuiteV2-Setup.exe"

    # 1. Wheel version + freshness
    Write-Host "`n[1/5] Wheel Version & Freshness" -ForegroundColor Cyan

    $latestSrcWheel = Get-ChildItem $dist -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 1

    if ($latestSrcWheel) {
        Write-Host "  Latest built wheel: $($latestSrcWheel.Name)"
    } else {
        Write-Host "  [WARN] No wheel found in dist\" -ForegroundColor Yellow
    }

    $payloadWheel = Get-ChildItem $payloadWheelDir -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

    if ($payloadWheel) {
        Write-Host "  Payload wheel:      $($payloadWheel.Name)"
    } else {
        Write-Host "  [WARN] No wheel found in installer_payload\wheel" -ForegroundColor Yellow
    }

    if ($latestSrcWheel -and $payloadWheel) {
        if ($latestSrcWheel.Name -eq $payloadWheel.Name) {
            Write-Host "  [OK] Wheel is latest." -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Wheel mismatch." -ForegroundColor Red
        }
    }

    # 2. Payload hash
    Write-Host "`n[2/5] Payload Hash" -ForegroundColor Cyan

    if (Test-Path $payloadRoot) {
        $payloadHash = Get-ChildItem $payloadRoot -Recurse -File |
                       Get-FileHash -Algorithm SHA256 |
                       Select-Object -ExpandProperty Hash |
                       Out-String
        $payloadHash = $payloadHash.Trim()
        Write-Host "  SHA256 (payload): $payloadHash"
    } else {
        Write-Host "  [WARN] Payload folder missing." -ForegroundColor Yellow
    }

    # 3. Installer EXE hash
    Write-Host "`n[3/5] Installer EXE Hash" -ForegroundColor Cyan

    if (Test-Path $installerExe) {
        $exeHash = (Get-FileHash $installerExe -Algorithm SHA256).Hash
        Write-Host "  Installer: $installerExe"
        Write-Host "  SHA256:    $exeHash"
    } else {
        Write-Host "  [FAIL] Installer EXE missing." -ForegroundColor Red
    }

    # 4. Script drift status
    Write-Host "`n[4/5] Script Drift Status" -ForegroundColor Cyan

    if (-not (Test-Path $payloadScripts)) {
        Write-Host "  [FAIL] installer_payload\scripts missing." -ForegroundColor Red
    } else {
        $srcFiles     = Get-ChildItem $srcScripts -File -Recurse
        $payloadFiles = Get-ChildItem $payloadScripts -File -Recurse

        $missing = @()
        $extra   = @()
        $drift   = @()

        foreach ($src in $srcFiles) {
            $rel  = $src.FullName.Substring($srcScripts.Length).TrimStart("\")
            $dest = Join-Path $payloadScripts $rel

            if (-not (Test-Path $dest)) {
                $missing += $rel
                continue
            }

            $hashA = (Get-FileHash $src.FullName  -Algorithm SHA256).Hash
            $hashB = (Get-FileHash $dest.FullName -Algorithm SHA256).Hash

            if ($hashA -ne $hashB) {
                $drift += $rel
            }
        }

        foreach ($p in $payloadFiles) {
            $rel = $p.FullName.Substring($payloadScripts.Length).TrimStart("\")
            $src = Join-Path $srcScripts $rel

            if (-not (Test-Path $src)) {
                $extra += $rel
            }
        }

        if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $drift.Count -eq 0) {
            Write-Host "  [OK] No script drift detected." -ForegroundColor Green
        } else {
            if ($missing.Count -gt 0) {
                Write-Host "  Missing:" -ForegroundColor Red
                $missing | ForEach-Object { Write-Host "    $_" }
            }
            if ($extra.Count -gt 0) {
                Write-Host "  Extra:" -ForegroundColor Red
                $extra | ForEach-Object { Write-Host "    $_" }
            }
            if ($drift.Count -gt 0) {
                Write-Host "  Drifted:" -ForegroundColor Red
                $drift | ForEach-Object { Write-Host "    $_" }
            }
        }
    }

    # 5. Deployment readiness
    Write-Host "`n[5/5] Deployment Readiness" -ForegroundColor Cyan

    $pre = Invoke-DeployPreflight
    if ($pre -eq 0) {
        Write-Host "  [READY] Deployment can proceed." -ForegroundColor Green
    } else {
        Write-Host "  [BLOCKED] Deployment cannot proceed. Preflight code: $pre" -ForegroundColor Red
    }

    Write-Host "`n=== End of Deploy-Suite Summary Report ===`n" -ForegroundColor Cyan
}

function Invoke-DeployHost {
    param(
        [Parameter(Mandatory = $true)][string]$IP,
        [switch]$BlueGreen
    )

    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return $pre }

    $Installer = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    & (Join-Path $Global:PrimaryRoot "deploy_suite.ps1") -TargetHost $IP -InstallerPath $Installer -BlueGreen:$BlueGreen
}

function Invoke-DeployCluster {
    param(
        [switch]$BlueGreen
    )

    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return $pre }

    & (Join-Path $Global:PrimaryRoot "build_and_deploy.ps1") -Deploy -BlueGreen:$BlueGreen
}

function Update-ForensicSuiteSecrets {
    Write-Host "`n>>> Provisioning REAL Secrets (env.json) to Cluster..." -ForegroundColor Magenta

    $LocalSecret = Join-Path $Global:PrimaryRoot "env.json"
    if (!(Test-Path $LocalSecret)) {
        Write-Error "CRITICAL: Local env.json missing!"
        return
    }

    foreach ($ip in $Global:ClusterIPs) {
        Write-Host ">>> Patching Node: $ip" -ForegroundColor Cyan
        scp -i $Global:SSHKey "$LocalSecret" "forensicuser@${ip}:F:\forensic_secrets\env.json"
        ssh -i $Global:SSHKey "forensicuser@$ip" "icacls F:\forensic_secrets\env.json /grant SYSTEM:(R)"
    }

    Write-Host "[SUCCESS] All nodes provisioned." -ForegroundColor Green
}

# =====================================================================
# 6. UNINSTALL / RECOVERY
# =====================================================================

function Invoke-ForensicUninstall {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Minimal", "Full")]
        [string]$Mode,
        [string]$TargetHost
    )

    $Hosts = if ($TargetHost) { @($TargetHost) } else { $Global:ClusterIPs }

    Write-Host "`n=== Forensic Suite Uninstall (V9.2) ===" -ForegroundColor Cyan
    Write-Host "Mode  : $Mode" -ForegroundColor Gray
    Write-Host "Hosts : $($Hosts -join ', ')" -ForegroundColor Gray

    foreach ($ip in $Hosts) {
        Write-Host "`n>>> Wiping Node $ip..." -ForegroundColor Cyan

        $paths = @(
            "C:\forensic_suite_v2",
            "C:\forensic_suite_v2_blue",
            "C:\forensic_suite_v2_green",
            "C:\forensic_suite_v2_installer.exe"
        )

        $svcCmd = if ($Mode -eq "Full") {
            "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue; " +
            "Set-Service btc_indexer -StartupType Disabled -ErrorAction SilentlyContinue; " +
            "Set-Service eth_indexer -StartupType Disabled -ErrorAction SilentlyContinue; " +
            "Set-Service tron_indexer -StartupType Disabled -ErrorAction SilentlyContinue; "
        } else {
            "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue; "
        }

        $rmCmd = ($paths | ForEach-Object {
                "Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue;"
            }) -join " "

        $cleanCmd = $svcCmd + $rmCmd

        ssh -i $Global:SSHKey "forensicuser@$ip" "powershell -Command `"$cleanCmd`""

        Write-Host "[OK] Node $ip wiped ($Mode)." -ForegroundColor Green
    }

    Write-Host "`n[COMPLETE] Uninstall orchestration finished." -ForegroundColor Green
}

# =====================================================================
# 7. HEALTH & DASHBOARD
# =====================================================================

function Get-StatusReport {
    Write-Host "`n=== FORENSIC SUITE CLUSTER STATUS (V9.3) ===" -ForegroundColor Cyan

    foreach ($ip in $Global:ClusterIPs) {

        # 1. Ping
        $ping = if (Test-Connection -ComputerName $ip -Count 1 -Quiet) { "UP" } else { "DOWN" }

        # Defaults
        $slot        = "UNKNOWN"
        $disk        = "UNKNOWN"
        $svc_btc     = "UNKNOWN"
        $svc_eth     = "UNKNOWN"
        $svc_tron    = "UNKNOWN"
        $svc_orch    = "UNKNOWN"
        $remoteWheel = "UNKNOWN"
        $remoteHash  = "UNKNOWN"
        $envStatus   = "UNKNOWN"

        if ($ping -eq "UP") {

            $slot = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if (Test-Path C:\forensic_suite_v2_blue) {\"BLUE\"}
                    elseif (Test-Path C:\forensic_suite_v2_green) {\"GREEN\"}
                    elseif (Test-Path C:\forensic_suite_v2) {\"LEGACY\"}
                    else {\"NONE\"}
                "'

            $svc_btc = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if(Get-Service btc_indexer -ErrorAction SilentlyContinue){
                        (Get-Service btc_indexer).Status
                    } else {\"MISSING\"}
                "'

            $svc_eth = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if(Get-Service eth_indexer -ErrorAction SilentlyContinue){
                        (Get-Service eth_indexer).Status
                    } else {\"MISSING\"}
                "'

            $svc_tron = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if(Get-Service tron_indexer -ErrorAction SilentlyContinue){
                        (Get-Service tron_indexer).Status
                    } else {\"MISSING\"}
                "'

            $svc_orch = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if(Get-Service forensic_orchestrator -ErrorAction SilentlyContinue){
                        (Get-Service forensic_orchestrator).Status
                    } else {\"MISSING\"}
                "'

            $disk = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "(Get-PSDrive C).Free/1GB -as [int]"'

            $remoteWheel = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    $w = Get-ChildItem C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1
                    if ($w) { $w.Name } else { \"NONE\" }
                "'

            $remoteHash = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    if (Test-Path C:\forensic_suite_v2*\installer_payload) {
                        Get-ChildItem C:\forensic_suite_v2*\installer_payload -Recurse -File |
                        Get-FileHash -Algorithm SHA256 |
                        Select-Object -ExpandProperty Hash |
                        Out-String
                    } else { \"NONE\" }
                "'

            $envStatus = ssh -i $Global:SSHKey "forensicuser@$ip" `
                'powershell -Command "
                    $envPath = Get-ChildItem C:\forensic_suite_v2*\config\env.json -ErrorAction SilentlyContinue
                    if (-not $envPath) { \"MISSING\"; return }
                    try {
                        $json = Get-Content $envPath.FullName | ConvertFrom-Json
                        if ($json.db_host -and $json.db_user -and $json.db_name) {
                            \"OK\"
                        } else {
                            \"INVALID\"
                        }
                    } catch {
                        \"INVALID\"
                    }
                "'
        }

        $healthy = ($ping -eq "UP") -and
                   ($svc_btc -match "Running") -and
                   ($svc_eth -match "Running") -and
                   ($svc_tron -match "Running") -and
                   ($svc_orch -match "Running") -and
                   ($envStatus -eq "OK")

        $color = if ($healthy) { "Green" }
                 elseif ($ping -eq "UP") { "Yellow" }
                 else { "Red" }

        Write-Host ""
        Write-Host ("  {0}" -f $ip) -ForegroundColor $color
        Write-Host ("     PING:        {0}" -f $ping)
        Write-Host ("     SLOT:        {0}" -f $slot)
        Write-Host ("     BTC:         {0}" -f $svc_btc)
        Write-Host ("     ETH:         {0}" -f $svc_eth)
        Write-Host ("     TRON:        {0}" -f $svc_tron)
        Write-Host ("     ORCH:        {0}" -f $svc_orch)
        Write-Host ("     FREE_C:      {0} GB" -f $disk)
        Write-Host ("     WHEEL:       {0}" -f $remoteWheel)
        Write-Host ("     PAYLOAD HASH:{0}" -f ($remoteHash.Trim()))
        Write-Host ("     ENV.JSON:    {0}" -f $envStatus)
    }

    Write-Host "`n=== END CLUSTER STATUS (V9.3) ===`n" -ForegroundColor Cyan
}

function Export-StatusReportJson {
    $ErrorActionPreference = "Stop"

    $results = @()

    foreach ($ip in $Global:ClusterIPs) {

        $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet

        $slot        = $null
        $disk        = $null
        $svc_btc     = $null
        $svc_eth     = $null
        $svc_tron    = $null
        $svc_orch    = $null
        $remoteWheel = $null
        $remoteHash  = $null
        $envStatus   = $null

        if ($ping) {
            $slot = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if (Test-Path C:\forensic_suite_v2_blue) {\"BLUE\"}
                elseif (Test-Path C:\forensic_suite_v2_green) {\"GREEN\"}
                elseif (Test-Path C:\forensic_suite_v2) {\"LEGACY\"}
                else {\"NONE\"}
            "'

            $svc_btc = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if(Get-Service btc_indexer -ErrorAction SilentlyContinue){
                    (Get-Service btc_indexer).Status
                } else {\"MISSING\"}
            "'

            $svc_eth = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if(Get-Service eth_indexer -ErrorAction SilentlyContinue){
                    (Get-Service eth_indexer).Status
                } else {\"MISSING\"}
            "'

            $svc_tron = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if(Get-Service tron_indexer -ErrorAction SilentlyContinue){
                    (Get-Service tron_indexer).Status
                } else {\"MISSING\"}
            "'

            $svc_orch = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if(Get-Service forensic_orchestrator -ErrorAction SilentlyContinue){
                    (Get-Service forensic_orchestrator).Status
                } else {\"MISSING\"}
            "'

            $disk = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "(Get-PSDrive C).Free/1GB -as [int]"'

            $remoteWheel = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                $w = Get-ChildItem C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1
                if ($w) { $w.Name } else { \"NONE\" }
            "'

            $remoteHash = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                if (Test-Path C:\forensic_suite_v2*\installer_payload) {
                    Get-ChildItem C:\forensic_suite_v2*\installer_payload -Recurse -File |
                    Get-FileHash -Algorithm SHA256 |
                    Select-Object -ExpandProperty Hash |
                    Out-String
                } else { \"NONE\" }
            "'

            $envStatus = ssh -i $Global:SSHKey "forensicuser@$ip" 'powershell -Command "
                $envPath = Get-ChildItem C:\forensic_suite_v2*\config\env.json -ErrorAction SilentlyContinue
                if (-not $envPath) { \"MISSING\"; return }
                try {
                    $json = Get-Content $envPath.FullName | ConvertFrom-Json
                    if ($json.db_host -and $json.db_user -and $json.db_name) {
                        \"OK\"
                    } else {
                        \"INVALID\"
                    }
                } catch {
                    \"INVALID\"
                }
            "'
        }

        $results += [pscustomobject]@{
            Host          = $ip
            Ping          = $ping
            Slot          = $slot
            DiskFreeGB    = $disk
            BTC_Service   = $svc_btc
            ETH_Service   = $svc_eth
            TRON_Service  = $svc_tron
            Orchestrator  = $svc_orch
            Wheel         = $remoteWheel
            PayloadHash   = $remoteHash.Trim()
            EnvJson       = $envStatus
        }
    }

    $results | ConvertTo-Json -Depth 6
}

function Compare-StatusReport {
    [CmdletBinding()]
    param(
        [string]$HostList = "F:\tools\forensic_hosts.txt",
        [string]$InstalledRoot = "C:\Program Files\ForensicSuiteV2"
    )

    $ErrorActionPreference = "Stop"

    Write-Host "`n=== CLUSTER DRIFT REPORT (Strict Allow‑List, V9.3.2) ===" -ForegroundColor Cyan

    # -----------------------------------------------------------------
    # 1. Strict allow‑list (same as RepoB + installer_payload)
    # -----------------------------------------------------------------
    $AllowedTopLevel = @(
        "forensic_suite_v2",
        "dashboards",
        "scripts",
        "wheel",
        "pyproject.toml",
        "indexers",
        "grafana"
    )

    $AllowedScripts = @(
        "install_services.ps1",
        "windows_orchestrator_service.ps1",
        "operator_console.ps1",
        "healthcheck.ps1",
        "healthcheck_core.py"
    )

    $AllowedRootFiles = @(
        "bootstrap.ps1",
        "env.template.json",
        "dot_env.template"
    )

    function Is‑AllowedPath {
        param([string]$RelPath)

        $p = $RelPath -replace "/", "\"

        foreach ($root in $AllowedTopLevel) {
            if ($p -like "$root\*") { return $true }
        }

        foreach ($s in $AllowedScripts) {
            if ($p -eq "scripts\$s") { return $true }
        }

        if ($p -like "wheel\*.whl") { return $true }

        if ($p -in $AllowedRootFiles) { return $true }

        return $false
    }

    # -----------------------------------------------------------------
    # 2. Load host list
    # -----------------------------------------------------------------
    if (!(Test-Path $HostList)) {
        Write-Host "[FAIL] Host list missing: $HostList" -ForegroundColor Red
        return
    }

    $Hosts = Get-Content $HostList | Where-Object { $_.Trim() -ne "" }

    if ($Hosts.Count -eq 0) {
        Write-Host "[FAIL] Host list is empty." -ForegroundColor Red
        return
    }

    # -----------------------------------------------------------------
    # 3. Gather file lists from each host
    # -----------------------------------------------------------------
    $ClusterFiles = @{}

    foreach ($host in $Hosts) {
        Write-Host "`n>>> Gathering file list from $host ..." -ForegroundColor Cyan

        $cmd = "Get-ChildItem '$InstalledRoot' -Recurse -File | ForEach-Object { `$_.FullName.Replace('$InstalledRoot\', '') }"
        $files = Invoke-Command -ComputerName $host -ScriptBlock { param($c) Invoke-Expression $c } -ArgumentList $cmd

        $Allowed = @()
        $Forbidden = @()

        foreach ($f in $files) {
            if (Is‑AllowedPath $f) {
                $Allowed += $f
            } else {
                $Forbidden += $f
            }
        }

        $ClusterFiles[$host] = [PSCustomObject]@{
            Allowed   = $Allowed
            Forbidden = $Forbidden
        }

        if ($Forbidden.Count -gt 0) {
            Write-Host "[WARN] Forbidden files on $host:" -ForegroundColor Yellow
            $Forbidden | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        } else {
            Write-Host "[OK] $host contains only runtime‑allowed files." -ForegroundColor Green
        }
    }

    # -----------------------------------------------------------------
    # 4. Cross‑node drift detection
    # -----------------------------------------------------------------
    Write-Host "`n=== Cluster Drift Detection ===" -ForegroundColor Cyan

    $BaselineHost = $Hosts[0]
    $Baseline = $ClusterFiles[$BaselineHost].Allowed

    foreach ($host in $Hosts) {
        if ($host -eq $BaselineHost) { continue }

        Write-Host "`n>>> Comparing $host against baseline $BaselineHost ..." -ForegroundColor Cyan

        $Current = $ClusterFiles[$host].Allowed

        $Missing = $Baseline | Where-Object { $_ -notin $Current }
        $Extra   = $Current  | Where-Object { $_ -notin $Baseline }

        if ($Missing.Count -eq 0 -and $Extra.Count -eq 0) {
            Write-Host "[OK] $host matches baseline exactly." -ForegroundColor Green
        } else {
            Write-Host "[DRIFT] Differences detected on $host:" -ForegroundColor Red

            if ($Missing.Count -gt 0) {
                Write-Host "  Missing files:" -ForegroundColor Red
                $Missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }

            if ($Extra.Count -gt 0) {
                Write-Host "  Extra files:" -ForegroundColor Red
                $Extra | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }
        }
    }

    Write-Host "`n=== END CLUSTER DRIFT REPORT ===`n" -ForegroundColor Cyan
}

# =====================================================================
# 8. HELP (V9.3)
# =====================================================================

function Get-ForensicSuiteHelp {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "        FORENSIC SUITE WORKSPACE — OPERATOR HELP (V9.3)     " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Authoritative Repo (Repo A): $Global:PrimaryRoot" -ForegroundColor Gray
    Write-Host "Runtime Mirror   (Repo B):  C:\forensic_suite_v2\forensic_suite_v2" -ForegroundColor Gray
    Write-Host ""

    Write-Host "----------------------------" -ForegroundColor DarkCyan
    Write-Host " CORE WORKFLOWS (V9.3.2)     " -ForegroundColor DarkCyan
    Write-Host "----------------------------" -ForegroundColor DarkCyan

    Write-Host "Update-ForensicSuiteDev" -ForegroundColor Yellow
    Write-Host "  Dry-run only:   Update-ForensicSuiteDev" -ForegroundColor Gray
    Write-Host "  Full apply:     Update-ForensicSuiteDev -Apply" -ForegroundColor Gray
    Write-Host "  Pipeline:" -ForegroundColor Gray
    Write-Host "    • Preflight (Repo A + Repo B validators)" -ForegroundColor Gray
    Write-Host "    • Mapping regeneration (V9.3 exclusion-aware)" -ForegroundColor Gray
    Write-Host "    • DryRun (V9.3)" -ForegroundColor Gray
    Write-Host "    • Apply (atomic temp mirror → atomic swap)" -ForegroundColor Gray
    Write-Host "    • Validate (V9.3 strict suite scope)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Clear-ForensicSuiteAll" -ForegroundColor Yellow
    Write-Host "  Cleans Repo A + Repo B, validates both, enforces runtime-only Repo B." -ForegroundColor Gray
    Write-Host ""

    Write-Host "Test-ForensicSuiteAll" -ForegroundColor Yellow
    Write-Host "  Runs combined validator (Repo A + Repo B)." -ForegroundColor Gray
    Write-Host ""

    Write-Host "Invoke-Preflight" -ForegroundColor Yellow
    Write-Host "  Ensures both repos are clean before any build or sync." -ForegroundColor Gray
    Write-Host ""

    Write-Host "Invoke-BuildSuite" -ForegroundColor Yellow
    Write-Host "  Full deterministic build pipeline:" -ForegroundColor Gray
    Write-Host "    • Wheel build" -ForegroundColor Gray
    Write-Host "    • Payload refresh" -ForegroundColor Gray
    Write-Host "    • Installer EXE build" -ForegroundColor Gray
    Write-Host "    • Post-install validation" -ForegroundColor Gray
    Write-Host "    • Installer-payload integrity validation (V9.3)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "safe-build" -ForegroundColor Yellow
    Write-Host "  Clear-ForensicSuiteAll → Invoke-BuildSuite (safe, deterministic build)." -ForegroundColor Gray
    Write-Host ""

    Write-Host "repair" -ForegroundColor Yellow
    Write-Host "  Clear-ForensicSuiteAll → Update-ForensicSuiteDev -Apply (repair runtime mirror)." -ForegroundColor Gray
    Write-Host ""

    Write-Host "repair-installer-payload" -ForegroundColor Yellow
    Write-Host "  Auto-repairs installer_payload (wheel, scripts, contamination cleanup)." -ForegroundColor Gray
    Write-Host ""

    Write-Host ""
    Write-Host "---------------------------" -ForegroundColor DarkCyan
    Write-Host " DEPLOYMENT COMMANDS       " -ForegroundColor DarkCyan
    Write-Host "---------------------------" -ForegroundColor DarkCyan

    Write-Host "Invoke-DeployPreflight" -ForegroundColor Yellow
    Write-Host "  Validates installer payload, EXE, and deployment scripts before any deploy." -ForegroundColor Gray
    Write-Host ""

    Write-Host "Get-DeploySuiteSummary" -ForegroundColor Yellow
    Write-Host "  Deployment readiness report:" -ForegroundColor Gray
    Write-Host "    • Wheel version" -ForegroundColor Gray
    Write-Host "    • Payload hash" -ForegroundColor Gray
    Write-Host "    • Installer EXE hash" -ForegroundColor Gray
    Write-Host "    • Script drift status" -ForegroundColor Gray
    Write-Host "    • Deploy-Suite preflight result" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Invoke-DeployHost" -ForegroundColor Yellow
    Write-Host "  Deploys suite to a single host (Blue/Green aware)." -ForegroundColor Gray

    Write-Host "Invoke-DeployCluster" -ForegroundColor Yellow
    Write-Host "  Deploys suite to all cluster nodes (Blue/Green aware)." -ForegroundColor Gray

    Write-Host "Update-ForensicSuiteSecrets" -ForegroundColor Yellow
    Write-Host "  Secure SCP + ACL propagation of secrets to hosts." -ForegroundColor Gray

    Write-Host ""
    Write-Host "---------------------------" -ForegroundColor DarkCyan
    Write-Host " RUNTIME / OPERATIONS      " -ForegroundColor DarkCyan
    Write-Host "---------------------------" -ForegroundColor DarkCyan

    Write-Host "Get-StatusReport" -ForegroundColor Yellow
    Write-Host "  Human-readable cluster dashboard: ping, services, slot, disk, wheel, payload hash, env.json." -ForegroundColor Gray

    Write-Host "Export-StatusReportJson" -ForegroundColor Yellow
    Write-Host "  Machine-readable JSON status feed for dashboards." -ForegroundColor Gray

    Write-Host "Compare-StatusReport" -ForegroundColor Yellow
    Write-Host "  Cluster drift detector (wheel, payload hash, env.json, services, slot)." -ForegroundColor Gray

    Write-Host "dashboard" -ForegroundColor Yellow
    Write-Host "  Opens the suite dashboard (local operator view)." -ForegroundColor Gray

    Write-Host "Invoke-ForensicUninstall" -ForegroundColor Yellow
    Write-Host "  Stops services → disables → removes suite folders." -ForegroundColor Gray

    Write-Host ""
    Write-Host "---------------------------" -ForegroundColor DarkCyan
    Write-Host " ALIASES (V9.3)            " -ForegroundColor DarkCyan
    Write-Host "---------------------------" -ForegroundColor DarkCyan

    Write-Host "syncdev            → Update-ForensicSuiteDev" -ForegroundColor Gray
    Write-Host "cleanall           → Clear-ForensicSuiteAll" -ForegroundColor Gray
    Write-Host "validate           → Test-ForensicSuiteAll" -ForegroundColor Gray
    Write-Host "repair             → repair" -ForegroundColor Gray
    Write-Host "safebuild          → safe-build" -ForegroundColor Gray
    Write-Host "payloadfix         → repair-installer-payload" -ForegroundColor Gray
    Write-Host "statusjson         → Export-StatusReportJson" -ForegroundColor Gray
    Write-Host "statusdiff         → Compare-StatusReport" -ForegroundColor Gray
    Write-Host "exclusiontest      → Run exclusion pattern tester" -ForegroundColor Gray
    Write-Host "exclusioncoverage  → Full exclusion map coverage report" -ForegroundColor Gray
    Write-Host "exclusiontree      → Color-coded exclusion tree visualizer" -ForegroundColor Gray
    Write-Host "exclusiondoctor    → Run all exclusion diagnostics" -ForegroundColor Gray

    Write-Host ""
    Write-Host "---------------------------" -ForegroundColor DarkCyan
    Write-Host " V9.3 EXCLUSION MODEL      " -ForegroundColor DarkCyan
    Write-Host "---------------------------" -ForegroundColor DarkCyan

    Write-Host "Repo B is enforced as a STRICT runtime-only mirror." -ForegroundColor Gray
    Write-Host "The following categories NEVER flow into Repo B:" -ForegroundColor Gray
    Write-Host "  • __pycache__, *.pyc, *.pyo" -ForegroundColor Gray
    Write-Host "  • Dev docs: *.md, *.txt, *.drawio, *.png" -ForegroundColor Gray
    Write-Host "  • Build artifacts: dist/, build/, wheel/, *.spec" -ForegroundColor Gray
    Write-Host "  • Installer artifacts: *.exe, *.msi, *.iss, Output/" -ForegroundColor Gray
    Write-Host "  • Orchestrator scripts: windows_orchestrator_service.ps1, install_services.ps1" -ForegroundColor Gray
    Write-Host "  • Checkpoints: eth_checkpoint.json, *.checkpoint.json" -ForegroundColor Gray
    Write-Host "  • Test files: test_install.ps1, tests/" -ForegroundColor Gray
    Write-Host ""
    Write-Host "These exclusions are enforced by:" -ForegroundColor Gray
    Write-Host "  • Mapping generator (V9.3)" -ForegroundColor Gray
    Write-Host "  • Sync‑DevTrees.DryRun (V9.3)" -ForegroundColor Gray
    Write-Host "  • Sync‑DevTrees.Apply (V9.3)" -ForegroundColor Gray
    Write-Host "  • Sync‑DevTrees.Validate (V9.3)" -ForegroundColor Gray
    Write-Host "  • Exclusion diagnostics: exclusiontest / exclusioncoverage / exclusiontree / exclusiondoctor" -ForegroundColor Gray
    Write-Host ""

    Write-Host "---------------------------" -ForegroundColor DarkCyan
    Write-Host " ATOMIC SYNC MODEL         " -ForegroundColor DarkCyan

    Write-Host "Sync‑Dev -Apply performs:" -ForegroundColor Gray
    Write-Host "  1. Build temp mirror at F:\DEVELOPMENT\Repo_B\forensic_suite_v2_tmp" -ForegroundColor Gray
    Write-Host "  2. Backup Repo B → F:\tools\RepoB_Backups" -ForegroundColor Gray
    Write-Host "  3. Atomic rename swap (temp → Repo B)" -ForegroundColor Gray
    Write-Host "  4. Final validation (V9.3 strict)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host " Forensic Suite V9.3.2 — Deterministic, Runtime‑Only, Atomic  " -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# =====================================================================
# 9. PROMPT CUSTOMIZATION & EXPORTS
# =====================================================================

function prompt { "Forensic-Dev [$(Split-Path -Leaf $pwd)]> " }

Export-ModuleMember -Function `
    Clear-ForensicSuiteAll, Test-ForensicSuiteAll, Invoke-Preflight, `
    Update-ForensicSuiteDev, Update-ForensicSuiteValidation, Invoke-BuildSuiteSafe, Invoke-BuildSuite, `
    Invoke-DeployPreflight, Get-DeploySuiteSummary, `
    Invoke-DeployHost, Invoke-DeployCluster, Update-ForensicSuiteSecrets, `
    Invoke-ForensicUninstall, `
    Get-StatusReport, Export-StatusReportJson, Compare-StatusReport, `
    Get-ForensicSuiteHelp

Write-Host "`nForensic Suite Workspace V9.3.2 Loaded." -ForegroundColor Yellow
Write-Host "Modules Imported: Clear-ForensicSuiteAll, Test-ForensicSuiteAll, Invoke-Preflight, Update-ForensicSuiteDev, Update-ForensicSuiteValidation, Invoke-BuildSuiteSafe, Invoke-BuildSuite, Invoke-DeployPreflight, Get-DeploySuiteSummary, Invoke-DeployHost, Invoke-DeployCluster, Update-ForensicSuiteSecrets, Invoke-ForensicUninstall, Get-StatusReport, Export-StatusReportJson, Compare-StatusReport, Get-ForensicSuiteHelp" -ForegroundColor Yellow
